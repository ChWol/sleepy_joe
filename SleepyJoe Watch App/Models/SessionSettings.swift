import Foundation
import SwiftUI

// MARK: - Haptic Strength
enum HapticStrength: Int, Codable, CaseIterable, Identifiable {
    case gentle = 1
    case medium = 2
    case strong = 3
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .gentle: return "Sanft"
        case .medium: return "Mittel"
        case .strong: return "Stark"
        }
    }
    
    var icon: String {
        switch self {
        case .gentle: return "speaker.wave.1"
        case .medium: return "speaker.wave.2"
        case .strong: return "speaker.wave.3"
        }
    }
}

// MARK: - Session Settings
/// Persisted settings for the monitoring session.
/// All values are stored in UserDefaults via @AppStorage in the views.
struct SessionSettings: Codable, Equatable {
    /// Sensitivity of stillness detection (1 = least sensitive, 5 = most sensitive)
    var sensitivity: Int = 3
    
    /// Base interval (in minutes) between random preventive pings
    var pingIntervalMinutes: Int = 10
    
    /// Haptic feedback strength
    var hapticStrength: HapticStrength = .medium
    
    /// Whether motion-based sleep detection is enabled
    var enableMotionDetection: Bool = true
    
    /// Whether random preventive pings are enabled
    var enableRandomPings: Bool = true
    
    // MARK: - Computed Properties
    
    /// Stillness threshold derived from sensitivity level.
    /// Higher sensitivity = lower threshold = detects smaller amounts of stillness.
    var stillnessThreshold: Double {
        switch sensitivity {
        case 1: return 0.12   // Very tolerant – only deep stillness triggers
        case 2: return 0.08
        case 3: return 0.05   // Balanced default
        case 4: return 0.03
        case 5: return 0.015  // Very sensitive – slight stillness triggers
        default: return 0.05
        }
    }
    
    /// How many seconds of stillness before triggering an alert.
    /// More sensitive = shorter delay.
    var alertDelaySeconds: TimeInterval {
        switch sensitivity {
        case 1: return 45
        case 2: return 35
        case 3: return 25
        case 4: return 18
        case 5: return 12
        default: return 25
        }
    }
    
    /// Random ping interval range (seconds). Adds ±30% randomness around base interval.
    var pingIntervalRange: ClosedRange<TimeInterval> {
        let base = TimeInterval(pingIntervalMinutes * 60)
        let variance = base * 0.3
        return (base - variance)...(base + variance)
    }
    
    /// Number of haptic repetitions based on strength.
    var hapticRepetitions: Int {
        switch hapticStrength {
        case .gentle: return 2
        case .medium: return 4
        case .strong: return 7
        }
    }
    
    // MARK: - Persistence
    
    static let storageKey = "sessionSettings"
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    static func load() -> SessionSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(SessionSettings.self, from: data) else {
            return SessionSettings()
        }
        return settings
    }
}
