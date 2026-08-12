import Foundation

/// On-Device Adaptive Learning Engine.
/// Learns live from explicit user feedback (✓ True Positive vs ✕ False Alarm)
/// to automatically calibrate personal stillness thresholds and posture sensitivity.
@MainActor
final class AdaptiveLearningEngine: ObservableObject {
    
    // MARK: - Published State
    
    /// Learned adjustment to stillness duration (seconds, e.g. +0.4s to prevent false alarms)
    @Published var personalStillnessOffset: Double = 0.0
    
    /// Learned adjustment to pitch drop threshold (degrees)
    @Published var personalPitchOffset: Double = 0.0
    
    /// Count of confirmed sleep detections (True Positives)
    @Published var truePositivesCount: Int = 0
    
    /// Count of reported false alarms (False Positives)
    @Published var falsePositivesCount: Int = 0
    
    // MARK: - Computed Analytics
    
    /// Calculated accuracy percentage (0% to 100%)
    var precisionPercentage: Int {
        let total = truePositivesCount + falsePositivesCount
        guard total > 0 else { return 100 }
        return Int((Double(truePositivesCount) / Double(total)) * 100.0)
    }
    
    // MARK: - Persistence Keys
    
    private let stillnessOffsetKey = "learned_stillness_offset"
    private let pitchOffsetKey = "learned_pitch_offset"
    private let tpCountKey = "learned_tp_count"
    private let fpCountKey = "learned_fp_count"
    
    // MARK: - Init
    
    init() {
        loadCalibration()
    }
    
    // MARK: - Live Feedback Processing
    
    /// Register live user feedback and immediately calibrate parameters.
    func registerFeedback(wasTruePositive: Bool) {
        if wasTruePositive {
            truePositivesCount += 1
            // True Positive: Detection was correct! Slightly tighten delay for even faster response (-0.1s, min -0.5s)
            personalStillnessOffset = max(-0.5, personalStillnessOffset - 0.1)
            print("🎯 [AdaptiveLearning] Confirmed TRUE POSITIVE. Total TP: \(truePositivesCount), Offset: \(personalStillnessOffset)s")
        } else {
            falsePositivesCount += 1
            // False Alarm: Quiet sitting triggered alert. Increase required duration (+0.4s, max +3.0s) so it won't repeat
            personalStillnessOffset = min(3.0, personalStillnessOffset + 0.4)
            print("🛡️ [AdaptiveLearning] Reported FALSE POSITIVE. Total FP: \(falsePositivesCount), Offset: \(personalStillnessOffset)s")
        }
        
        saveCalibration()
    }
    
    /// Reset learned calibration back to factory defaults
    func resetCalibration() {
        personalStillnessOffset = 0.0
        personalPitchOffset = 0.0
        truePositivesCount = 0
        falsePositivesCount = 0
        saveCalibration()
    }
    
    // MARK: - Persistence
    
    private func saveCalibration() {
        let defaults = UserDefaults.standard
        defaults.set(personalStillnessOffset, forKey: stillnessOffsetKey)
        defaults.set(personalPitchOffset, forKey: pitchOffsetKey)
        defaults.set(truePositivesCount, forKey: tpCountKey)
        defaults.set(falsePositivesCount, forKey: fpCountKey)
    }
    
    private func loadCalibration() {
        let defaults = UserDefaults.standard
        personalStillnessOffset = defaults.double(forKey: stillnessOffsetKey)
        personalPitchOffset = defaults.double(forKey: pitchOffsetKey)
        truePositivesCount = defaults.integer(forKey: tpCountKey)
        falsePositivesCount = defaults.integer(forKey: fpCountKey)
    }
}
