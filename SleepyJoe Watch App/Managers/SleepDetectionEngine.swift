import Foundation

/// Fault-tolerant Multi-Sensor Fusion Engine for real-time sleep onset detection.
/// Integrates live adaptive learning offsets from AdaptiveLearningEngine.
@MainActor
final class SleepDetectionEngine: ObservableObject {
    
    // MARK: - Published State
    
    /// Total combined confidence score (0.0 to 1.0)
    @Published var totalConfidence: Double = 0.0
    
    /// Whether sleep onset is detected
    @Published var isSleepDetected: Bool = false
    
    /// Human-readable detection rationale (for debugging/logs)
    @Published var detectionReason: String = ""
    
    // MARK: - Private Properties
    
    private var confidenceStartTime: Date?
    
    // MARK: - Evaluation Logic
    
    func evaluate(
        motionManager: MotionManager,
        healthKitManager: HealthKitManager,
        settings: SessionSettings,
        adaptiveEngine: AdaptiveLearningEngine
    ) {
        var score: Double = 0.0
        var reasons: [String] = []
        
        // Calculate dynamically learned required stillness duration
        let requiredStillnessSeconds = max(1.0, settings.stillnessRequiredSeconds + adaptiveEngine.personalStillnessOffset)
        
        // 1. Micro-Jitter Stillness (+0.60)
        if motionManager.isStill && motionManager.stillDuration >= requiredStillnessSeconds {
            score += 0.60
            reasons.append("Stillness \(String(format: "%.1f", motionManager.stillDuration))s (+0.60)")
        }
        
        // 2. Posture Pitch Drop / Downward Tilt (+0.40)
        if motionManager.isPitchDropDetected {
            score += 0.40
            reasons.append("Pitch Tilt (+0.40)")
        }
        
        // 3. Heart Rate Drop (+0.35)
        if healthKitManager.heartRateDropPercentage >= 0.04 {
            score += 0.35
            reasons.append("HR Drop \(Int(healthKitManager.heartRateDropPercentage * 100))% (+0.35)")
        }
        
        totalConfidence = min(1.0, score)
        detectionReason = reasons.joined(separator: " | ")
        
        // High Sensitivity Threshold Evaluation
        let thresholdMet = totalConfidence >= settings.confidenceThreshold
        
        if thresholdMet {
            if confidenceStartTime == nil {
                confidenceStartTime = Date()
            }
            
            if let start = confidenceStartTime, Date().timeIntervalSince(start) >= 1.0 {
                isSleepDetected = true
            }
        } else {
            confidenceStartTime = nil
            isSleepDetected = false
        }
    }
    
    func reset() {
        totalConfidence = 0.0
        isSleepDetected = false
        detectionReason = ""
        confidenceStartTime = nil
    }
}
