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
struct SessionSettings: Codable, Equatable {
    /// Whether automatic learned sensitivity calibration is enabled
    var useAutoSensitivity: Bool = true
    
    /// Manual sensitivity level (1 = least sensitive, 5 = most sensitive) when auto sensitivity is disabled
    var sensitivity: Int = 3
    
    /// Base interval (in minutes) between random preventive pings (1, 5, 10, 15, 20)
    var pingIntervalMinutes: Int = 10
    
    /// Haptic feedback strength
    var hapticStrength: HapticStrength = .medium
    
    /// Whether motion-based sleep detection is enabled
    var enableMotionDetection: Bool = true
    
    /// Whether random preventive pings are enabled
    var enableRandomPings: Bool = true
    
    // MARK: - Dynamic Sensitivity Metrics
    
    /// Confidence threshold required to trigger sleep alert.
    var confidenceThreshold: Double {
        switch sensitivity {
        case 5: return 0.35
        case 4: return 0.45
        case 3: return 0.55
        case 2: return 0.65
        case 1: return 0.75
        default: return 0.55
        }
    }
    
    /// Minimum stillness duration (seconds) required before confidence builds up.
    var stillnessRequiredSeconds: Double {
        switch sensitivity {
        case 5: return 1.5
        case 4: return 2.5
        case 3: return 3.5
        case 2: return 5.0
        case 1: return 7.0
        default: return 3.5
        }
    }
    
    /// Micro-jitter stillness threshold derived from sensitivity.
    var stillnessThreshold: Double {
        switch sensitivity {
        case 5: return 0.10
        case 4: return 0.08
        case 3: return 0.05
        case 2: return 0.03
        case 1: return 0.015
        default: return 0.05
        }
    }
    
    /// Random ping interval range (seconds). Adds ±30% randomness around base interval.
    var pingIntervalRange: ClosedRange<TimeInterval> {
        let base = TimeInterval(pingIntervalMinutes * 60)
        let variance = max(10, base * 0.3)
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
