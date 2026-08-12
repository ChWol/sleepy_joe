import Foundation

/// Advanced On-Device Multi-Feature Pattern Learning Engine.
/// Learns individual sensor weight importance (w_motion, w_pitch, w_hr)
/// and feature-specific thresholds rather than just global scalar offsets.
@MainActor
final class AdaptiveLearningEngine: ObservableObject {
    
    // MARK: - Published State (Individual Sensor Weights & Thresholds)
    
    /// Learned weight for Motion Micro-Stillness (default 0.60)
    @Published var weightStillness: Double = 0.60
    
    /// Learned weight for Posture Pitch Drop (default 0.40)
    @Published var weightPitch: Double = 0.40
    
    /// Learned weight for Heart Rate Drop (default 0.35)
    @Published var weightHR: Double = 0.35
    
    /// Learned adjustment to required stillness duration (seconds)
    @Published var personalStillnessOffset: Double = 0.0
    
    /// Learned adjustment to overall confidence trigger threshold
    @Published var confidenceThresholdOffset: Double = 0.0
    
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
    
    private let wStillnessKey = "learned_w_stillness"
    private let wPitchKey = "learned_w_pitch"
    private let wHRKey = "learned_w_hr"
    private let stillnessOffsetKey = "learned_stillness_offset"
    private let confOffsetKey = "learned_conf_offset"
    private let tpCountKey = "learned_tp_count"
    private let fpCountKey = "learned_fp_count"
    
    // MARK: - Init
    
    init() {
        loadCalibration()
    }
    
    // MARK: - Multi-Feature Pattern Learning Algorithm
    
    /// Learns feature importance patterns from live feedback.
    /// If HR is uninformative, its weight is lowered.
    /// If motion stillness is critical, its weight is boosted.
    func registerFeedbackPattern(
        wasTruePositive: Bool,
        wasHRActive: Bool,
        wasPitchActive: Bool,
        wasStillnessActive: Bool
    ) {
        if wasTruePositive {
            truePositivesCount += 1
            
            // True Positive: Boost weights of sensors that correctly flagged sleep onset
            if wasStillnessActive { weightStillness = min(0.80, weightStillness + 0.03) }
            if wasPitchActive { weightPitch = min(0.60, weightPitch + 0.03) }
            if wasHRActive { weightHR = min(0.50, weightHR + 0.03) }
            
            personalStillnessOffset = max(-0.5, personalStillnessOffset - 0.1)
            confidenceThresholdOffset = max(-0.15, confidenceThresholdOffset - 0.02)
            
            print("🎯 [PatternLearning] TRUE POSITIVE: Weights (Still: \(weightStillness), Pitch: \(weightPitch), HR: \(weightHR))")
        } else {
            falsePositivesCount += 1
            
            // False Alarm: Penalize sensors that caused the false trigger
            if wasHRActive {
                // User's HR is noisy/uninformative -> lower HR weight
                weightHR = max(0.10, weightHR - 0.08)
            }
            if wasStillnessActive {
                // Increase stillness duration requirement
                personalStillnessOffset = min(3.0, personalStillnessOffset + 0.4)
            }
            if wasPitchActive {
                weightPitch = max(0.20, weightPitch - 0.05)
            }
            
            confidenceThresholdOffset = min(0.20, confidenceThresholdOffset + 0.04)
            
            print("🛡️ [PatternLearning] FALSE POSITIVE: Adjusted Weights (Still: \(weightStillness), Pitch: \(weightPitch), HR: \(weightHR))")
        }
        
        saveCalibration()
    }
    
    /// Reset learned calibration back to factory defaults
    func resetCalibration() {
        weightStillness = 0.60
        weightPitch = 0.40
        weightHR = 0.35
        personalStillnessOffset = 0.0
        confidenceThresholdOffset = 0.0
        truePositivesCount = 0
        falsePositivesCount = 0
        saveCalibration()
    }
    
    // MARK: - Persistence
    
    private func saveCalibration() {
        let defaults = UserDefaults.standard
        defaults.set(weightStillness, forKey: wStillnessKey)
        defaults.set(weightPitch, forKey: wPitchKey)
        defaults.set(weightHR, forKey: wHRKey)
        defaults.set(personalStillnessOffset, forKey: stillnessOffsetKey)
        defaults.set(confidenceThresholdOffset, forKey: confOffsetKey)
        defaults.set(truePositivesCount, forKey: tpCountKey)
        defaults.set(falsePositivesCount, forKey: fpCountKey)
    }
    
    private func loadCalibration() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: wStillnessKey) != nil {
            weightStillness = defaults.double(forKey: wStillnessKey)
            weightPitch = defaults.double(forKey: wPitchKey)
            weightHR = defaults.double(forKey: wHRKey)
        }
        personalStillnessOffset = defaults.double(forKey: stillnessOffsetKey)
        confidenceThresholdOffset = defaults.double(forKey: confOffsetKey)
        truePositivesCount = defaults.integer(forKey: tpCountKey)
        falsePositivesCount = defaults.integer(forKey: fpCountKey)
    }
}
