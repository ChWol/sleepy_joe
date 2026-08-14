import Foundation
import Combine
import WatchKit

/// Orchestrates the monitoring session by coordinating MotionManager, HealthKitManager,
/// SleepDetectionEngine, AdaptiveLearningEngine, TelemetryLogger, HapticManager,
/// and the on-device ML classifier pipeline (SleepMLClassifier, MLReplayBuffer, OnDeviceTrainer).
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
    @Published var settings: SessionSettings
    
    /// Controls whether the 5-second discreet live feedback bar (✓/✕) is shown after returning to Active
    @Published var showFeedbackPrompt: Bool = false
    
    /// Whether the 10-second Refractory Grace Period is active after returning to Active
    @Published var isGracePeriodActive: Bool = false
    
    // MARK: - Child Managers
    
    let motionManager: MotionManager
    let healthKitManager: HealthKitManager
    let sleepDetectionEngine: SleepDetectionEngine
    let adaptiveEngine: AdaptiveLearningEngine
    let telemetryLogger: TelemetryLogger
    let hapticManager: HapticManager
    
    // MARK: - ML Pipeline Components
    
    let mlClassifier: SleepMLClassifier
    let mlReplayBuffer: MLReplayBuffer
    let onDeviceTrainer: OnDeviceTrainer
    let backgroundTrainingScheduler: BackgroundTrainingScheduler
    
    // MARK: - Private Properties
    
    private var sessionStartTime: Date?
    private var elapsedTimer: Timer?
    private var monitoringTask: Task<Void, Never>?
    private var randomPingTask: Task<Void, Never>?
    private var feedbackDismissTask: Task<Void, Never>?
    private var gracePeriodTask: Task<Void, Never>?
    private var nextPingTime: Date?
    private var pingCountdownTimer: Timer?
    
    private var consecutiveAlerts: Int = 0
    
    /// Cached anchor samples loaded once from bundle
    private let anchorSamples: [LabeledFeatureVector]
    
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
        
        // ML Pipeline
        self.mlClassifier = SleepMLClassifier()
        self.mlReplayBuffer = MLReplayBuffer()
        self.onDeviceTrainer = OnDeviceTrainer()
        self.backgroundTrainingScheduler = BackgroundTrainingScheduler()
        self.anchorSamples = AnchorSampleLoader.loadAnchorSamples()
        
        // Schedule background consolidation training
        backgroundTrainingScheduler.scheduleConsolidation()
    }
    
    // MARK: - Live Feedback Handler
    
    /// Submit live feedback (✓ True Positive vs ✕ False Alarm).
    /// Records clean 5-second telemetry dataset sample, updates adaptive weights,
    /// extracts features for ML training, and triggers immediate on-device model update.
    func submitFeedback(wasTruePositive: Bool) {
        hapticManager.stopCurrentSequence()
        
        let labelString = wasTruePositive ? "true_positive" : "false_positive"
        telemetryLogger.recordSample(
            label: labelString,
            pitchBuffer: motionManager.pitchDegreesHistory,
            motionBuffer: motionManager.motionDeltaHistory,
            heartRate: healthKitManager.currentHeartRate,
            hrDrop: healthKitManager.heartRateDropPercentage
        )
        
        adaptiveEngine.registerFeedbackPattern(
            wasTruePositive: wasTruePositive,
            wasHRActive: sleepDetectionEngine.wasHRActive,
            wasPitchActive: sleepDetectionEngine.wasPitchActive,
            wasStillnessActive: sleepDetectionEngine.wasStillnessActive
        )
        
        // ── ML Training Pipeline ──
        // Extract features and add to replay buffer
        let features = sleepDetectionEngine.lastExtractedFeatures
        if features.count == 16 {
            let mlLabel = wasTruePositive ? "sleep" : "awake"
            mlReplayBuffer.addSample(label: mlLabel, features: features)
            
            // Trigger immediate on-device training (15 epochs, ~20ms, no UI lag)
            triggerImmediateTraining()
        }
        
        // If feedback was tapped while actively alerting, return to monitoring cleanly
        if state == .alerting {
            consecutiveAlerts = 0
            state = .monitoring
            startGracePeriod(seconds: 10)
        }
        
        WKInterfaceDevice.current().play(.click)
        
        feedbackDismissTask?.cancel()
        showFeedbackPrompt = false
    }
    
    // MARK: - ML Training
    
    /// Runs a quick 15-epoch training cycle on the background queue (~20ms).
    /// Combines anchor samples with user feedback buffer, duplicates sleep samples ×3.
    private func triggerImmediateTraining() {
        guard let modelURL = onDeviceTrainer.getCompiledModelURL() else {
            print("[SessionManager] ML Training skipped — no compiled model found")
            return
        }
        
        let userSamples = mlReplayBuffer.allSamples()
        guard !userSamples.isEmpty else { return }
        
        print("[SessionManager] Starting immediate ML training with \(userSamples.count) user + \(anchorSamples.count) anchor samples")
        
        onDeviceTrainer.train(
            compiledModelURL: modelURL,
            samples: userSamples,
            anchorSamples: anchorSamples,
            epochs: 15
        ) { [weak self] success in
            guard let self = self else { return }
            if success {
                print("[SessionManager] Immediate ML training completed — reloading model")
                self.mlClassifier.reloadModel()
            } else {
                print("[SessionManager] Immediate ML training failed")
            }
        }
    }
    
    // MARK: - Reset Learning
    
    /// Resets all adaptive learning: heuristic calibration offsets, ML replay buffer,
    /// and user-trained model (reverts to factory bundle model).
    func resetAllLearning() {
        adaptiveEngine.resetCalibration()
        mlReplayBuffer.clear()
        
        let fileManager = FileManager.default
        if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let trainedModelURL = docsURL.appendingPathComponent("SleepyClassifier.mlmodelc")
            if fileManager.fileExists(atPath: trainedModelURL.path) {
                try? fileManager.removeItem(at: trainedModelURL)
            }
        }
        
        mlClassifier.reloadModel()
    }
    
    // MARK: - Session Control
    
    func startSession() {
        guard state == .idle else { return }
        
        motionManager.updateSettings(settings)
        hapticManager.updateSettings(settings)
        
        alertCount = 0
        consecutiveAlerts = 0
        sessionStartTime = Date()
        elapsedTime = 0
        showFeedbackPrompt = false
        isGracePeriodActive = false
        sleepDetectionEngine.reset()
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.sessionStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
        
        if settings.enableMotionDetection {
            motionManager.startTracking()
            healthKitManager.startMonitoring()
        }
        
        startMonitoringLoop()
        
        if settings.enableRandomPings {
            startRandomPingLoop()
        }
        
        state = .monitoring
        WKInterfaceDevice.current().play(.start)
    }
    
    func stopSession() {
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
        healthKitManager.stopMonitoring()
        hapticManager.stopCurrentSequence()
        sleepDetectionEngine.reset()
        
        sessionStartTime = nil
        nextPingTime = nil
        consecutiveAlerts = 0
        showFeedbackPrompt = false
        isGracePeriodActive = false
        
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
                
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5s
                
                guard self.state != .idle else { return }
                guard self.settings.enableMotionDetection else { continue }
                
                if self.isGracePeriodActive {
                    self.sleepDetectionEngine.reset()
                    continue
                }
                
                // Instant Waking Motion Check during Alerting State
                if self.state == .alerting {
                    // Instantly cancel alarm if user performs a high-energy wake gesture (hand shake score > 0.40 or posture reset)
                    let isHighEnergyWakeGesture = (self.motionManager.movementScore > 0.40) || (!self.motionManager.isPitchDropDetected && self.motionManager.movementScore > 0.20)
                    
                    if isHighEnergyWakeGesture {
                        // Instant cancellation on high-energy waking gesture!
                        self.hapticManager.stopCurrentSequence()
                        self.consecutiveAlerts = 0
                        self.state = .monitoring
                        self.startGracePeriod(seconds: 10)
                        self.startFeedbackPrompt(seconds: 5)
                    }
                    continue
                }
                
                // Normal Monitoring Evaluation (with ML ensemble)
                self.sleepDetectionEngine.evaluate(
                    motionManager: self.motionManager,
                    healthKitManager: self.healthKitManager,
                    settings: self.settings,
                    adaptiveEngine: self.adaptiveEngine,
                    mlClassifier: self.mlClassifier
                )
                
                if self.sleepDetectionEngine.isSleepDetected {
                    self.triggerAlert()
                } else if self.sleepDetectionEngine.totalConfidence >= 0.50 {
                    if self.state == .monitoring {
                        self.state = .warning
                    }
                } else {
                    if self.state == .warning {
                        self.state = .monitoring
                    }
                }
            }
        }
    }
    
    private func triggerAlert() {
        guard state != .alerting else { return }
        
        state = .alerting
        alertCount += 1
        consecutiveAlerts += 1
        
        // Show feedback buttons IMMEDIATELY upon alerting
        feedbackDismissTask?.cancel()
        showFeedbackPrompt = true
        
        // Rings continuously until user clearly moves or labels
        hapticManager.playContinuousAlarm(escalated: consecutiveAlerts >= 2)
    }
    
    private func startFeedbackPrompt(seconds: Double) {
        guard settings.useAutoSensitivity else { return }
        
        showFeedbackPrompt = true
        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self.showFeedbackPrompt = false
            }
        }
    }
    
    private func startGracePeriod(seconds: Double) {
        isGracePeriodActive = true
        gracePeriodTask?.cancel()
        gracePeriodTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self.isGracePeriodActive = false
            }
        }
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
