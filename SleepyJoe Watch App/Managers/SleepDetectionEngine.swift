import Foundation

/// Fault-tolerant Multi-Sensor Fusion Engine for real-time sleep onset detection.
/// Computes a total confidence score C_total ∈ [0.0, 1.0] from Pitch Drop (+0.50),
/// Micro-Jitter Stillness (+0.50), and Heart Rate Drop (+0.35).
///
/// Trigger Condition: C_total >= 0.70 for >3 seconds.
/// This ensures rapid detection whether the arm is hanging in the lap OR resting flat on a desk.
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
    
    func evaluate(motionManager: MotionManager, healthKitManager: HealthKitManager) {
        var score: Double = 0.0
        var reasons: [String] = []
        
        // 1. Posture Pitch Drop (+0.50)
        if motionManager.isPitchDropDetected {
            score += 0.50
            reasons.append("Pitch Drop (+0.50)")
        }
        
        // 2. Micro-Jitter Nulllinie (+0.50)
        if motionManager.isStill && motionManager.stillDuration >= 4.0 {
            score += 0.50
            reasons.append("Micro-Stillness \(Int(motionManager.stillDuration))s (+0.50)")
        }
        
        // 3. Heart Rate Drop (+0.35)
        if healthKitManager.heartRateDropPercentage >= 0.06 {
            score += 0.35
            reasons.append("HR Drop \(Int(healthKitManager.heartRateDropPercentage * 100))% (+0.35)")
        }
        
        totalConfidence = min(1.0, score)
        detectionReason = reasons.joined(separator: " | ")
        
        // Trigger threshold check: C_total >= 0.70
        let thresholdMet = totalConfidence >= 0.70
        
        if thresholdMet {
            if confidenceStartTime == nil {
                confidenceStartTime = Date()
            }
            
            if let start = confidenceStartTime, Date().timeIntervalSince(start) >= 3.0 {
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
