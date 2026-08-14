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
    
    /// Play a continuous looping alarm sequence that rings until explicitly stopped by user action (wake gesture or label tap).
    func playContinuousAlarm(escalated: Bool = false) {
        stopCurrentSequence()
        currentLevel = escalated ? .alarm : .wake
        print("🚨 [HapticManager] Started Continuous Looping Alarm (escalated: \(escalated))")
        
        hapticTask = Task {
            isPlaying = true
            var cycle = 0
            
            while !Task.isCancelled {
                cycle += 1
                
                if escalated || cycle > 2 {
                    // Escalated high-intensity bursts
                    for _ in 0..<4 {
                        guard !Task.isCancelled else { break }
                        let type = aggressiveTypes.randomElement() ?? .notification
                        WKInterfaceDevice.current().play(type)
                        let delay = Double.random(in: 0.12...0.25)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    
                    guard !Task.isCancelled else { break }
                    WKInterfaceDevice.current().play(.directionUp)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    WKInterfaceDevice.current().play(.notification)
                } else {
                    // Moderate wake bursts
                    let pattern = cycle % 3
                    switch pattern {
                    case 0:
                        await playPattern_DoubleTap(count: 2)
                    case 1:
                        await playPattern_Ascending(count: 3)
                    default:
                        await playPattern_IrregularBurst(count: 2)
                    }
                }
                
                // Short pause between repeating alarm bursts (0.6s to 1.0s)
                let gap = Double.random(in: 0.6...1.0)
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
            
            isPlaying = false
        }
    }
    
    /// Play a single wake-up sequence
    func playWake() {
        playContinuousAlarm(escalated: false)
    }
    
    /// Play an escalated alarm sequence
    func playAlarm() {
        playContinuousAlarm(escalated: true)
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
