import Foundation
import WatchKit

/// Manages all haptic feedback with built-in randomness to prevent habituation.
@MainActor
final class HapticManager: ObservableObject {
    
    // MARK: - Types
    
    enum AlertLevel: Int, Comparable {
        case nudge = 1   // Gentle preventive ping
        case wake = 2    // Moderate "hey, stay awake"
        case alarm = 3   // Aggressive "WAKE UP"
        
        static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Published State
    
    /// Whether a haptic sequence is currently playing
    @Published var isPlaying: Bool = false
    
    /// Current escalation level
    @Published var currentLevel: AlertLevel = .nudge
    
    // MARK: - Private Properties
    
    private var hapticTask: Task<Void, Never>?
    private var settings: SessionSettings
    
    private let gentleTypes: [WKHapticType] = [.click, .directionUp]
    private let moderateTypes: [WKHapticType] = [.notification, .retry, .start]
    private let aggressiveTypes: [WKHapticType] = [.notification, .retry, .stop, .start]
    
    // MARK: - Init
    
    init(settings: SessionSettings = .load()) {
        self.settings = settings
    }
    
    // MARK: - Public Methods
    
    func updateSettings(_ newSettings: SessionSettings) {
        self.settings = newSettings
    }
    
    /// Play a single gentle nudge (used for random preventive pings)
    func playNudge() {
        stopCurrentSequence()
        currentLevel = .nudge
        print("🔔 [HapticManager] Triggered Gentle Nudge Ping")
        
        hapticTask = Task {
            isPlaying = true
            let taps = settings.hapticStrength == .gentle ? 1 : 2
            for _ in 0..<taps {
                guard !Task.isCancelled else { break }
                let type = gentleTypes.randomElement() ?? .click
                WKInterfaceDevice.current().play(type)
                
                let delay = Double.random(in: 0.3...0.8)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            isPlaying = false
        }
    }
    
    /// Play a wake-up sequence (moderate intensity, used when stillness first detected)
    func playWake() {
        stopCurrentSequence()
        currentLevel = .wake
        print("⚠️ [HapticManager] Triggered Wake Alarm Sequence")
        
        hapticTask = Task {
            isPlaying = true
            let pattern = Int.random(in: 0...2)
            
            switch pattern {
            case 0:
                await playPattern_DoubleTap(count: settings.hapticRepetitions)
            case 1:
                await playPattern_Ascending(count: settings.hapticRepetitions)
            default:
                await playPattern_IrregularBurst(count: settings.hapticRepetitions)
            }
            
            isPlaying = false
        }
    }
    
    /// Play an alarm sequence (maximum intensity, escalated alert)
    func playAlarm() {
        stopCurrentSequence()
        currentLevel = .alarm
        print("🚨 [HapticManager] Triggered Escalated Alarm Kaskade")
        
        hapticTask = Task {
            isPlaying = true
            let repetitions = settings.hapticRepetitions + 3
            
            for _ in 0..<repetitions {
                guard !Task.isCancelled else { break }
                let type = aggressiveTypes.randomElement() ?? .notification
                WKInterfaceDevice.current().play(type)
                let delay = Double.random(in: 0.15...0.4)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            guard !Task.isCancelled else { isPlaying = false; return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            for _ in 0..<3 {
                guard !Task.isCancelled else { break }
                await playPattern_TripleBurst()
                let pause = Double.random(in: 0.5...1.0)
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            }
            
            isPlaying = false
        }
    }
    
    /// Play a short sample corresponding to the selected haptic strength level.
    /// Each level uses a distinctly different physical Taptic Engine pattern.
    func playSample(for strength: HapticStrength) {
        stopCurrentSequence()
        print("⚡ [HapticManager] Playing Sample for Strength: \(strength.label)")
        
        hapticTask = Task {
            isPlaying = true
            switch strength {
            case .gentle:
                // Sanft: Ein einziger, spürbarer sanfter Tap
                WKInterfaceDevice.current().play(.directionUp)
                
            case .medium:
                // Mittel: Ein deutlicher Doppel-Pulse (System Notification)
                WKInterfaceDevice.current().play(.notification)
                
            case .strong:
                // Stark: Eine dreifache, ausgeprägte Vibrations-Kaskade
                WKInterfaceDevice.current().play(.notification)
                try? await Task.sleep(nanoseconds: 120_000_000)
                WKInterfaceDevice.current().play(.retry)
                try? await Task.sleep(nanoseconds: 120_000_000)
                WKInterfaceDevice.current().play(.directionDown)
            }
            isPlaying = false
        }
    }
    
    /// Immediately stop any playing haptic sequence
    func stopCurrentSequence() {
        hapticTask?.cancel()
        hapticTask = nil
        isPlaying = false
    }
    
    // MARK: - Haptic Patterns
    
    private func playPattern_DoubleTap(count: Int) async {
        for _ in 0..<count {
            guard !Task.isCancelled else { return }
            let type = moderateTypes.randomElement() ?? .notification
            WKInterfaceDevice.current().play(type)
            try? await Task.sleep(nanoseconds: 150_000_000)
            WKInterfaceDevice.current().play(type)
            
            let gap = Double.random(in: 0.6...1.2)
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
        }
    }
    
    private func playPattern_Ascending(count: Int) async {
        let allTypes: [WKHapticType] = [.click, .directionUp, .start, .notification, .retry]
        for i in 0..<min(count, allTypes.count) {
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(allTypes[i])
            let gap = max(0.3, 1.0 - Double(i) * 0.15)
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
        }
    }
    
    private func playPattern_IrregularBurst(count: Int) async {
        for _ in 0..<count {
            guard !Task.isCancelled else { return }
            let burstSize = Int.random(in: 1...3)
            for _ in 0..<burstSize {
                guard !Task.isCancelled else { return }
                let type = moderateTypes.randomElement() ?? .retry
                WKInterfaceDevice.current().play(type)
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            let gap = Double.random(in: 0.8...1.5)
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
        }
    }
    
    private func playPattern_TripleBurst() async {
        for _ in 0..<3 {
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
