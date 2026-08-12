import Foundation
import Combine
import WatchKit

/// Orchestrates the entire monitoring session by coordinating MotionManager,
/// HealthKitManager, SleepDetectionEngine, AdaptiveLearningEngine, and HapticManager.
@MainActor
final class SessionManager: ObservableObject {
    
    // MARK: - Types
    
    enum SessionState: Equatable {
        case idle       // No active session
        case monitoring // Actively watching for sleep
        case warning    // Stillness/confidence building
        case alerting   // Haptic alert in progress
    }
    
    // MARK: - Published State
    
    @Published var state: SessionState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var alertCount: Int = 0
    @Published var nextPingIn: TimeInterval = 0
    @Published var settings: SessionSettings
    
    /// Controls whether the 5-second discreet live feedback bar (✓/✕) is shown
    @Published var showFeedbackPrompt: Bool = false
    
    // MARK: - Child Managers
    
    let motionManager: MotionManager
    let healthKitManager: HealthKitManager
    let sleepDetectionEngine: SleepDetectionEngine
    let adaptiveEngine: AdaptiveLearningEngine
    let hapticManager: HapticManager
    
    // MARK: - Private Properties
    
    private var sessionStartTime: Date?
    private var elapsedTimer: Timer?
    private var monitoringTask: Task<Void, Never>?
    private var randomPingTask: Task<Void, Never>?
    private var feedbackDismissTask: Task<Void, Never>?
    private var nextPingTime: Date?
    private var pingCountdownTimer: Timer?
    
    private var consecutiveAlerts: Int = 0
    
    // MARK: - Init
    
    init() {
        let loadedSettings = SessionSettings.load()
        self.settings = loadedSettings
        self.motionManager = MotionManager(settings: loadedSettings)
        self.healthKitManager = HealthKitManager()
        self.sleepDetectionEngine = SleepDetectionEngine()
        self.adaptiveEngine = AdaptiveLearningEngine()
        self.hapticManager = HapticManager(settings: loadedSettings)
    }
    
    // MARK: - Live Feedback Handler
    
    /// Submit live feedback (✓ True Positive vs ✕ False Alarm) and update multi-feature sensor weights
    func submitFeedback(wasTruePositive: Bool) {
        adaptiveEngine.registerFeedbackPattern(
            wasTruePositive: wasTruePositive,
            wasHRActive: sleepDetectionEngine.wasHRActive,
            wasPitchActive: sleepDetectionEngine.wasPitchActive,
            wasStillnessActive: sleepDetectionEngine.wasStillnessActive
        )
        
        // Confirmation tap
        WKInterfaceDevice.current().play(.click)
        
        // Hide prompt immediately
        feedbackDismissTask?.cancel()
        showFeedbackPrompt = false
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
        sleepDetectionEngine.reset()
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.sessionStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
        
        if settings.enableMotionDetection {
            motionManager.startTracking()
            Task {
                let _ = await healthKitManager.requestAuthorization()
                healthKitManager.startMonitoring()
            }
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
        
        motionManager.stopTracking()
        healthKitManager.stopMonitoring()
        hapticManager.stopCurrentSequence()
        sleepDetectionEngine.reset()
        
        sessionStartTime = nil
        nextPingTime = nil
        consecutiveAlerts = 0
        showFeedbackPrompt = false
        
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
                
                // Evaluate Multi-Sensor Sleep Detection Engine with dynamic settings & live adaptive offsets
                self.sleepDetectionEngine.evaluate(
                    motionManager: self.motionManager,
                    healthKitManager: self.healthKitManager,
                    settings: self.settings,
                    adaptiveEngine: self.adaptiveEngine
                )
                
                if self.sleepDetectionEngine.isSleepDetected {
                    self.triggerAlert()
                } else if self.sleepDetectionEngine.totalConfidence >= 0.50 {
                    if self.state == .monitoring {
                        self.state = .warning
                    }
                } else {
                    if self.state == .warning || self.state == .alerting {
                        self.hapticManager.stopCurrentSequence()
                        self.consecutiveAlerts = 0
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
        
        // Show discreet 5-second live feedback bar (✓/✕)
        showFeedbackPrompt = true
        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds
            if !Task.isCancelled {
                self.showFeedbackPrompt = false
            }
        }
        
        switch consecutiveAlerts {
        case 1:
            hapticManager.playWake()
        case 2:
            hapticManager.playAlarm()
        default:
            hapticManager.playAlarm()
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.state == .alerting {
                self.state = .monitoring
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
