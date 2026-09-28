import Foundation
import Combine
import WatchKit

/// Orchestrates the monitoring session by coordinating MotionManager, HealthKitManager,
/// SleepDetectionEngine, AdaptiveLearningEngine, TelemetryLogger, HapticManager,
/// and the small buffer of explicitly labeled personal patterns.
/// Instantly cancels alarms upon high-energy waking motion (hand shake / arm posture reset) without artificial time delays.
@MainActor
final class SessionManager: ObservableObject {
    
    // MARK: - Types
    
    enum SessionState: Equatable {
        case idle       // No active session
        case monitoring // Actively watching for sleep (Green / Active)
        case warning    // Stillness/confidence building
        case alerting   // Haptic alert in progress (Vibrating)
    }
    
    // MARK: - Published State
    
    @Published var state: SessionState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var alertCount: Int = 0
    @Published var nextPingIn: TimeInterval = 0
    @Published var isMotionAvailable: Bool = true
    @Published var isHeartRateAvailable: Bool = false
    @Published var hasCheckedHealthKitAuthorization: Bool = false
    @Published var settings: SessionSettings
    
    /// Controls whether the 5-second discreet live feedback bar (✓/✕) is shown after returning to Active
    @Published var showFeedbackPrompt: Bool = false
    
    /// Whether the 10-second Refractory Grace Period is active after returning to Active
    @Published var isGracePeriodActive: Bool = false
    
    /// Temporary confirmation state when user manually logs a sleep onset by tapping the gauge
    @Published var manualLogConfirmed: Bool = false
    
    // MARK: - Child Managers
    
    let motionManager: MotionManager
    let healthKitManager: HealthKitManager
    let sleepDetectionEngine: SleepDetectionEngine
    let adaptiveEngine: AdaptiveLearningEngine
    let telemetryLogger: TelemetryLogger
    let hapticManager: HapticManager
    
    // Confirmed user patterns are used directly for conservative few-shot learning.
    let mlReplayBuffer: MLReplayBuffer
    
    // MARK: - Private Properties
    
    private var sessionStartTime: Date?
    private var elapsedTimer: Timer?
    private var monitoringTask: Task<Void, Never>?
    private var randomPingTask: Task<Void, Never>?
    private var feedbackDismissTask: Task<Void, Never>?
    private var gracePeriodTask: Task<Void, Never>?
    private var manualLogResetTask: Task<Void, Never>?
    private var nextPingTime: Date?
    private var pingCountdownTimer: Timer?
    
    private struct DetectionSnapshot {
        let capturedAt: Date
        let pitch: [Double]
        let motion: [Double]
        let x: [Float]
        let y: [Float]
        let z: [Float]
        let heartRate: Double
        let hrDrop: Double
        let features: [Float]
        let wasHRActive: Bool
        let wasPitchActive: Bool
        let wasStillnessActive: Bool
    }
    private var feedbackSnapshot: DetectionSnapshot?
    
    // MARK: - Init
    
    init() {
        let loadedSettings = SessionSettings.load()
        self.settings = loadedSettings
        self.motionManager = MotionManager(settings: loadedSettings)
        self.healthKitManager = HealthKitManager()
        self.sleepDetectionEngine = SleepDetectionEngine()
        self.adaptiveEngine = AdaptiveLearningEngine()
        self.telemetryLogger = TelemetryLogger()
        self.hapticManager = HapticManager(settings: loadedSettings)
        
        self.mlReplayBuffer = MLReplayBuffer()
    }
    
    // MARK: - Manual Sleep Onset Logging
    
    /// Proactively logs an unflagged sleep onset / nodding off event directly (e.g. tapping the center gauge).
    /// Captures a missed event when the user explicitly reports drowsiness.
    @discardableResult
    func logManualSleepOnset() -> Bool {
        guard (state == .monitoring || state == .warning),
              !isGracePeriodActive, !showFeedbackPrompt,
              let snapshot = captureSnapshot() else { return false }

        recordTelemetry(snapshot, label: "missed_alert")
        adaptiveEngine.registerFeedbackPattern(
            wasTruePositive: true,
            wasHRActive: snapshot.wasHRActive,
            wasPitchActive: snapshot.wasPitchActive,
            wasStillnessActive: snapshot.wasStillnessActive
        )
        if snapshot.x.count == 50 {
            mlReplayBuffer.addSample(label: "sleep", features: snapshot.features)
        }
        WKInterfaceDevice.current().play(.success)
        
        manualLogConfirmed = true
        manualLogResetTask?.cancel()
        manualLogResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                self.manualLogConfirmed = false
            }
        }
        
        startGracePeriod(seconds: 10)
        return true
    }
    
    // MARK: - Live Feedback Handler
    
    /// Submit live feedback (✓ True Positive vs ✕ False Alarm).
    /// Labels the sensor window captured before the alarm and wake gesture.
    func submitFeedback(wasTruePositive: Bool) {
        guard showFeedbackPrompt, let snapshot = feedbackSnapshot else { return }
        recordDecision(wasTruePositive ? "feedback_confirmed" : "feedback_false_alarm")
        feedbackSnapshot = nil
        hapticManager.stopCurrentSequence()
        
        let labelString = wasTruePositive ? "true_positive" : "false_positive"
        recordTelemetry(snapshot, label: labelString)
        
        adaptiveEngine.registerFeedbackPattern(
            wasTruePositive: wasTruePositive,
            wasHRActive: snapshot.wasHRActive,
            wasPitchActive: snapshot.wasPitchActive,
            wasStillnessActive: snapshot.wasStillnessActive
        )
        if snapshot.x.count == 50 {
            mlReplayBuffer.addSample(label: wasTruePositive ? "sleep" : "awake", features: snapshot.features)
        }
        
        // If feedback was tapped while actively alerting, return to monitoring cleanly
        if state == .alerting {
            recordDecision("alarm_cancelled_by_feedback")
            state = .monitoring
            startGracePeriod(seconds: 10)
        }
        
        WKInterfaceDevice.current().play(.click)
        
        feedbackDismissTask?.cancel()
        showFeedbackPrompt = false
    }
    
    private func captureSnapshot() -> DetectionSnapshot? {
        guard let lastSample = motionManager.lastSampleDate,
              Date().timeIntervalSince(lastSample) < 1,
              motionManager.rawAccelXHistory.count >= 30 else { return nil }
        let x = motionManager.rawAccelXHistory
        let y = motionManager.rawAccelYHistory
        let z = motionManager.rawAccelZHistory
        let pitch = motionManager.pitchDegreesHistory
        return DetectionSnapshot(
            capturedAt: lastSample,
            pitch: pitch,
            motion: motionManager.motionDeltaHistory,
            x: x, y: y, z: z,
            heartRate: healthKitManager.hasFreshHeartRate ? healthKitManager.currentHeartRate : 0,
            hrDrop: healthKitManager.hasFreshHeartRate ? healthKitManager.heartRateDropPercentage : 0,
            features: FeatureExtractor.extractFeatures(x: x, y: y, z: z, pitch: pitch.map(Float.init)),
            wasHRActive: sleepDetectionEngine.wasHRActive,
            wasPitchActive: sleepDetectionEngine.wasPitchActive,
            wasStillnessActive: sleepDetectionEngine.wasStillnessActive
        )
    }

    private func recordTelemetry(_ snapshot: DetectionSnapshot, label: String) {
        telemetryLogger.recordSample(
            label: label,
            timestamp: snapshot.capturedAt,
            pitchBuffer: snapshot.pitch,
            motionBuffer: snapshot.motion,
            accelerationX: snapshot.x,
            accelerationY: snapshot.y,
            accelerationZ: snapshot.z,
            heartRate: snapshot.heartRate,
            hrDrop: snapshot.hrDrop
        )
    }
    
    // MARK: - Reset Learning
    
    /// Resets all adaptive learning: heuristic calibration offsets, ML replay buffer,
    /// and user-trained model (reverts to factory bundle model).
    func resetAllLearning() {
        adaptiveEngine.resetCalibration()
        deleteStoredSensorData()
        let fileManager = FileManager.default
        if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let trainedModelURL = docsURL.appendingPathComponent("SleepyClassifier.mlmodelc")
            if fileManager.fileExists(atPath: trainedModelURL.path) {
                try? fileManager.removeItem(at: trainedModelURL)
            }
        }
        feedbackSnapshot = nil
    }

    /// Deletes explicitly labeled sensor windows and personal example patterns.
    /// Calibration counters and sensitivity preferences remain intact.
    func deleteStoredSensorData() {
        mlReplayBuffer.clear()
        telemetryLogger.clearTelemetry()
        feedbackSnapshot = nil
    }
    
    // MARK: - Session Control
    
    func startSession() {
        guard state == .idle else { return }
        
        motionManager.updateSettings(settings)
        hapticManager.updateSettings(settings)
        
        alertCount = 0
        sessionStartTime = Date()
        elapsedTime = 0
        showFeedbackPrompt = false
        feedbackSnapshot = nil
        isGracePeriodActive = false
        isMotionAvailable = false
        isHeartRateAvailable = false
        hasCheckedHealthKitAuthorization = false
        sleepDetectionEngine.reset()
        motionManager.onWakeGesture = { [weak self] in
            self?.finishAlertAfterWakeGesture()
        }
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.sessionStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
        
        if settings.enableMotionDetection {
            motionManager.startTracking()
            isMotionAvailable = motionManager.isTracking
            if motionManager.isTracking {
                Task { [weak self] in
                    guard let self = self else { return }
                    let authorized = await self.healthKitManager.requestAuthorization()
                    guard self.state != .idle else { return }
                    self.hasCheckedHealthKitAuthorization = true
                    if authorized, self.state != .idle {
                        self.healthKitManager.startMonitoring()
                    } else {
                        self.recordDecision("heart_rate_unavailable")
                    }
                }
            }
        }
        
        startMonitoringLoop()
        
        if settings.enableRandomPings {
            startRandomPingLoop()
        }
        
        state = .monitoring
        recordDecision("session_started")
        WKInterfaceDevice.current().play(.start)
    }
    
    func stopSession() {
        guard state != .idle else { return }
        recordDecision("session_stopped")
        state = .idle
        
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        pingCountdownTimer?.invalidate()
        pingCountdownTimer = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        randomPingTask?.cancel()
        randomPingTask = nil
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        gracePeriodTask?.cancel()
        gracePeriodTask = nil
        
        motionManager.stopTracking()
        motionManager.onWakeGesture = nil
        healthKitManager.stopMonitoring()
        hapticManager.stopCurrentSequence()
        sleepDetectionEngine.reset()
        
        sessionStartTime = nil
        nextPingTime = nil
        showFeedbackPrompt = false
        feedbackSnapshot = nil
        isGracePeriodActive = false
        isHeartRateAvailable = false
        hasCheckedHealthKitAuthorization = false
        manualLogResetTask?.cancel()
        manualLogConfirmed = false
        
        WKInterfaceDevice.current().play(.stop)
    }
    
    func updateSettings(_ newSettings: SessionSettings) {
        settings = newSettings
        settings.save()
        motionManager.updateSettings(newSettings)
        hapticManager.updateSettings(newSettings)
    }
    
    // MARK: - Monitoring Loop
    
    private func startMonitoringLoop() {
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                
                guard self.state != .idle else { return }
                guard self.settings.enableMotionDetection else { continue }
                let sampleIsFresh = self.motionManager.lastSampleDate.map {
                    Date().timeIntervalSince($0) < 2
                } ?? (self.elapsedTime < 3)
                let motionAvailable = self.motionManager.isTracking && sampleIsFresh
                if self.isMotionAvailable != motionAvailable {
                    self.isMotionAvailable = motionAvailable
                    self.recordDecision(motionAvailable ? "motion_restored" : "motion_gap")
                }
                let heartRateAvailable = self.healthKitManager.hasFreshHeartRate
                if self.isHeartRateAvailable != heartRateAvailable {
                    self.isHeartRateAvailable = heartRateAvailable
                    self.recordDecision(heartRateAvailable ? "heart_rate_available" : "heart_rate_gap")
                }
                
                if self.isGracePeriodActive {
                    continue
                }
                
                // Instant Waking Motion Check during Alerting State
                if self.state == .alerting {
                    // Instantly cancel alarm if user performs a high-energy wake gesture (hand shake score > 0.40 or posture reset)
                    let isHighEnergyWakeGesture = (self.motionManager.recentMovementScore > 0.40) || (!self.motionManager.isPitchDropDetected && self.motionManager.recentMovementScore > 0.20)
                    
                    if isHighEnergyWakeGesture {
                        // Instant cancellation on high-energy waking gesture!
                        self.finishAlertAfterWakeGesture()
                    }
                    continue
                }
                
                // Current multi-sensor rule evaluation with personal hard negatives.
                self.sleepDetectionEngine.evaluate(
                    motionManager: self.motionManager,
                    healthKitManager: self.healthKitManager,
                    settings: self.settings,
                    adaptiveEngine: self.adaptiveEngine,
                    feedbackSamples: self.settings.useAutoSensitivity ? self.mlReplayBuffer.entries : []
                )
                
                if self.sleepDetectionEngine.isSleepDetected {
                    self.triggerAlert()
                } else if self.sleepDetectionEngine.isWarningCandidate {
                    if self.state == .monitoring {
                        self.recordDecision("sleep_candidate")
                        self.state = .warning
                    }
                } else {
                    if self.state == .warning {
                        self.recordDecision("candidate_cleared")
                        self.state = .monitoring
                    }
                }
            }
        }
    }
    
    private func triggerAlert() {
        guard state != .alerting else { return }
        feedbackSnapshot = captureSnapshot()
        recordDecision("alarm_fired")
        
        state = .alerting
        alertCount += 1
        
        // Show feedback buttons IMMEDIATELY upon alerting
        feedbackDismissTask?.cancel()
        showFeedbackPrompt = true
        
        // Rings continuously until user clearly moves or labels
        hapticManager.playContinuousAlarm()
    }

    private func finishAlertAfterWakeGesture() {
        guard state == .alerting else { return }
        recordDecision("alarm_cancelled_by_wake_gesture")
        hapticManager.stopCurrentSequence()
        state = .monitoring
        startGracePeriod(seconds: 10)
        startFeedbackPrompt(seconds: 5)
    }
    
    private func startFeedbackPrompt(seconds: Double) {
        showFeedbackPrompt = true
        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self.showFeedbackPrompt = false
                self.feedbackSnapshot = nil
            }
        }
    }
    
    private func startGracePeriod(seconds: Double) {
        recordDecision("grace_period_started")
        isGracePeriodActive = true
        sleepDetectionEngine.reset()
        gracePeriodTask?.cancel()
        gracePeriodTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self.isGracePeriodActive = false
                self.recordDecision("grace_period_ended")
            }
        }
    }

    private func recordDecision(_ event: String) {
        let now = Date()
        let sampleAge = motionManager.lastSampleDate.map { max(0, now.timeIntervalSince($0)) }
        telemetryLogger.recordDecision(DetectionDecisionTrace(
            timestamp: now,
            event: event,
            reason: sleepDetectionEngine.detectionReason,
            confidence: sleepDetectionEngine.totalConfidence,
            confidenceThreshold: sleepDetectionEngine.activeConfidenceThreshold,
            stillnessThreshold: sleepDetectionEngine.activeStillnessThreshold,
            requiredStillnessSeconds: sleepDetectionEngine.activeRequiredStillnessSeconds,
            stillnessDuration: motionManager.stillDuration,
            movementScore: motionManager.recentMovementScore,
            pitchCue: sleepDetectionEngine.wasPitchActive,
            heartRateCue: sleepDetectionEngine.wasHRActive,
            motionSampleAge: sampleAge
        ))
    }
    
    // MARK: - Random Ping Loop
    
    private func startRandomPingLoop() {
        randomPingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                let range = self.settings.pingIntervalRange
                let interval = Double.random(in: range)
                self.nextPingTime = Date().addingTimeInterval(interval)
                
                self.startPingCountdown()
                
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                guard !Task.isCancelled else { return }
                guard self.state == .monitoring || self.state == .warning else { continue }
                guard !self.isGracePeriodActive else { continue }
                
                self.hapticManager.playNudge()
            }
        }
    }
    
    private func startPingCountdown() {
        pingCountdownTimer?.invalidate()
        pingCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let pingTime = self.nextPingTime else { return }
                let remaining = pingTime.timeIntervalSinceNow
                self.nextPingIn = max(0, remaining)
            }
        }
    }
}
