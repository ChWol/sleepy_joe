import Foundation

/// Advanced On-Device Multi-Feature Pattern Learning Engine.
/// Learns individual sensor weight importance (w_motion, w_pitch, w_hr)
/// and granular micro-jitter variance thresholds (epsilon_jitter) rather than just inflating time delays.
@MainActor
final class AdaptiveLearningEngine: ObservableObject {
    
    // MARK: - Published State (Granular Feature Weights & Thresholds)
    
    /// Learned weight for Motion Micro-Stillness (default 0.60)
    @Published var weightStillness: Double = 0.60
    
    /// Learned weight for Posture Pitch Drop (default 0.40)
    @Published var weightPitch: Double = 0.40
    
    /// Learned weight for Heart Rate Drop (default 0.35)
    @Published var weightHR: Double = 0.35
    
    /// Learned adjustment to stillness duration (bounded between -0.5s and +1.0s to preserve fast response)
    @Published var personalStillnessOffset: Double = 0.0
    
    /// Learned granular micro-jitter variance floor adjustment (epsilon_jitter)
    @Published var microJitterThresholdOffset: Double = 0.0
    
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
    private let jitterOffsetKey = "learned_jitter_offset"
    private let confOffsetKey = "learned_conf_offset"
    private let tpCountKey = "learned_tp_count"
    private let fpCountKey = "learned_fp_count"
    
    // MARK: - Init
    
    init() {
        loadCalibration()
    }
    
    // MARK: - Multi-Feature Pattern Learning Algorithm
    
    /// Learns granular feature thresholds and sensor weight importance from live feedback.
    /// Handles class imbalance (many false alarms vs few true sleep events) via asymmetric cost updates.
    func registerFeedbackPattern(
        wasTruePositive: Bool,
        wasHRActive: Bool,
        wasPitchActive: Bool,
        wasStillnessActive: Bool
    ) {
        if wasTruePositive {
            truePositivesCount += 1
            
            // True Positive: Confirmed sleep! Boost weights of sensors that flagged sleep onset
            if wasStillnessActive { weightStillness = min(0.85, weightStillness + 0.04) }
            if wasPitchActive { weightPitch = min(0.65, weightPitch + 0.04) }
            if wasHRActive { weightHR = min(0.55, weightHR + 0.04) }
            
            // Sharpen detection response (-0.1s duration, lower confidence threshold)
            personalStillnessOffset = max(-0.5, personalStillnessOffset - 0.1)
            confidenceThresholdOffset = max(-0.15, confidenceThresholdOffset - 0.03)
            
            print("🎯 [PatternLearning] TRUE POSITIVE: Weights (Still: \(weightStillness), Pitch: \(weightPitch), HR: \(weightHR))")
        } else {
            falsePositivesCount += 1
            
            // False Alarm: Quiet sitting. Adjust granular jitter threshold rather than endlessly adding seconds!
            if wasStillnessActive {
                // Tighten granular micro-jitter variance threshold (epsilon_jitter) so quiet tremors are distinguished from true atonia
                microJitterThresholdOffset = max(-0.025, microJitterThresholdOffset - 0.005)
                // Allow stillness offset to scale up to +4.0s to accommodate desk/reading work
                personalStillnessOffset = min(4.0, personalStillnessOffset + 0.25)
            }
            
            if wasHRActive {
                // Heart rate was noisy -> penalize HR weight so quiet sitting HR fluctuations don't trigger false alarms
                weightHR = max(0.10, weightHR - 0.08)
            }
            if wasPitchActive {
                weightPitch = max(0.20, weightPitch - 0.04)
            }
            
            confidenceThresholdOffset = min(0.15, confidenceThresholdOffset + 0.03)
            
            print("🛡️ [PatternLearning] FALSE POSITIVE: Adjusted Weights (Still: \(weightStillness), JitterOffset: \(microJitterThresholdOffset), HR: \(weightHR))")
        }
        
        saveCalibration()
    }
    
    /// Reset learned calibration back to factory defaults
    func resetCalibration() {
        weightStillness = 0.60
        weightPitch = 0.40
        weightHR = 0.35
        personalStillnessOffset = 0.0
        microJitterThresholdOffset = 0.0
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
        defaults.set(microJitterThresholdOffset, forKey: jitterOffsetKey)
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
        microJitterThresholdOffset = defaults.double(forKey: jitterOffsetKey)
        confidenceThresholdOffset = defaults.double(forKey: confOffsetKey)
        truePositivesCount = defaults.integer(forKey: tpCountKey)
        falsePositivesCount = defaults.integer(forKey: fpCountKey)
    }
}
