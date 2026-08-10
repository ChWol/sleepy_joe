import Foundation
import Combine
import WatchKit

/// Orchestrates the entire monitoring session by coordinating MotionManager
/// and HapticManager into a coherent wake-detection system.
///
/// Runs two parallel strategies:
/// 1. **Reactive**: Monitors accelerometer → detects stillness → triggers escalating haptics
/// 2. **Proactive**: Random timer pings → preventive nudges to keep user awake
///
/// State Machine:
/// ```
/// idle → monitoring → (stillness detected) → warning → alerting
///                   ↑         (movement)          ↓
///                   └─────────────────────────────┘
/// ```
@MainActor
final class SessionManager: ObservableObject {
    
    // MARK: - Types
    
    enum SessionState: Equatable {
        case idle       // No active session
        case monitoring // Actively watching for sleep
        case warning    // Stillness detected, about to alert
        case alerting   // Haptic alert in progress
    }
    
    // MARK: - Published State
    
    @Published var state: SessionState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var alertCount: Int = 0
    @Published var nextPingIn: TimeInterval = 0
    @Published var settings: SessionSettings
    
    // MARK: - Child Managers
    
    let motionManager: MotionManager
    let hapticManager: HapticManager
    
    // MARK: - Private Properties
    
    private var sessionStartTime: Date?
    private var elapsedTimer: Timer?
    private var monitoringTask: Task<Void, Never>?
    private var randomPingTask: Task<Void, Never>?
    private var nextPingTime: Date?
    private var pingCountdownTimer: Timer?
    
    /// Tracks consecutive alerts without movement (for escalation)
    private var consecutiveAlerts: Int = 0
    
    // MARK: - Init
    
    init() {
        let loadedSettings = SessionSettings.load()
        self.settings = loadedSettings
        self.motionManager = MotionManager(settings: loadedSettings)
        self.hapticManager = HapticManager(settings: loadedSettings)
    }
    
    // MARK: - Session Control
    
    /// Start a new monitoring session
    func startSession() {
        guard state == .idle else { return }
        
        // Apply current settings to child managers
        motionManager.updateSettings(settings)
        hapticManager.updateSettings(settings)
        
        // Reset counters
        alertCount = 0
        consecutiveAlerts = 0
        sessionStartTime = Date()
        elapsedTime = 0
        
        // Start elapsed time timer (updates every second)
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.sessionStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
        
        // Start motion tracking
        if settings.enableMotionDetection {
            motionManager.startTracking()
        }
        
        // Start monitoring loop (watches for stillness)
        startMonitoringLoop()
        
        // Start random ping timer
        if settings.enableRandomPings {
            startRandomPingLoop()
        }
        
        state = .monitoring
        
        // Confirmation tap that session started
        WKInterfaceDevice.current().play(.start)
    }
    
    /// Stop the current session and clean up
    func stopSession() {
        state = .idle
        
        // Cancel all timers and tasks
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        pingCountdownTimer?.invalidate()
        pingCountdownTimer = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        randomPingTask?.cancel()
        randomPingTask = nil
        
        // Stop child managers
        motionManager.stopTracking()
        hapticManager.stopCurrentSequence()
        
        sessionStartTime = nil
        nextPingTime = nil
        consecutiveAlerts = 0
        
        // Confirmation tap that session ended
        WKInterfaceDevice.current().play(.stop)
    }
    
    /// Update settings and propagate to child managers
    func updateSettings(_ newSettings: SessionSettings) {
        settings = newSettings
        settings.save()
        motionManager.updateSettings(newSettings)
        hapticManager.updateSettings(newSettings)
    }
    
    // MARK: - Monitoring Loop
    
    /// Main monitoring loop: watches MotionManager state and triggers alerts
    private func startMonitoringLoop() {
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5s
                
                guard self.state != .idle else { return }
                guard self.settings.enableMotionDetection else { continue }
                
                if self.motionManager.isStill {
                    let stillFor = self.motionManager.stillDuration
                    
                    if stillFor >= self.settings.alertDelaySeconds {
                        // Stillness exceeded threshold → trigger alert
                        self.triggerAlert()
                    } else if stillFor >= self.settings.alertDelaySeconds * 0.7 {
                        // Approaching threshold → enter warning state
                        if self.state == .monitoring {
                            self.state = .warning
                        }
                    }
                } else {
                    // Movement detected → back to monitoring
                    if self.state == .warning || self.state == .alerting {
                        self.hapticManager.stopCurrentSequence()
                        self.consecutiveAlerts = 0
                        self.state = .monitoring
                    }
                }
            }
        }
    }
    
    /// Trigger a haptic alert with escalation based on consecutive alerts
    private func triggerAlert() {
        guard state != .alerting else { return }
        
        state = .alerting
        alertCount += 1
        consecutiveAlerts += 1
        
        // Escalate based on consecutive alerts without movement
        switch consecutiveAlerts {
        case 1:
            hapticManager.playWake()
        case 2:
            hapticManager.playAlarm()
        default:
            // After 3+ alerts, keep playing alarm with increasing intensity
            hapticManager.playAlarm()
        }
        
        // Auto-reset to monitoring after a few seconds so we can re-check
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
            if self.state == .alerting {
                self.state = .monitoring
            }
        }
    }
    
    // MARK: - Random Ping Loop
    
    /// Random ping timer: fires at random intervals within the configured range
    private func startRandomPingLoop() {
        randomPingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                // Calculate next random interval
                let range = self.settings.pingIntervalRange
                let interval = Double.random(in: range)
                self.nextPingTime = Date().addingTimeInterval(interval)
                
                // Start countdown display timer
                self.startPingCountdown()
                
                // Wait for the interval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                guard !Task.isCancelled else { return }
                guard self.state == .monitoring || self.state == .warning else { continue }
                
                // Fire a gentle nudge
                self.hapticManager.playNudge()
            }
        }
    }
    
    /// Updates the nextPingIn countdown display
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
