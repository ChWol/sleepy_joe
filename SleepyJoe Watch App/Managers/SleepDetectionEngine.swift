import Foundation

/// Fault-tolerant Multi-Sensor Fusion Engine for real-time sleep onset detection.
/// Integrates granular micro-jitter variance thresholds and per-sensor feature weights.
@MainActor
final class SleepDetectionEngine: ObservableObject {
    
    // MARK: - Published State
    
    /// Total combined confidence score (0.0 to 1.0)
    @Published var totalConfidence: Double = 0.0
    
    /// Whether sleep onset is detected
    @Published var isSleepDetected: Bool = false
    
    /// Human-readable detection rationale
    @Published var detectionReason: String = ""
    
    /// Active feature contributions during last evaluation
    @Published var wasStillnessActive: Bool = false
    @Published var wasPitchActive: Bool = false
    @Published var wasHRActive: Bool = false
    
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
        
        let stillnessOffset = settings.useAutoSensitivity ? adaptiveEngine.personalStillnessOffset : 0.0
        let requiredStillnessSeconds = max(1.0, settings.stillnessRequiredSeconds + stillnessOffset)
        
        let confOffset = settings.useAutoSensitivity ? adaptiveEngine.confidenceThresholdOffset : 0.0
        let activeThreshold = max(0.20, settings.confidenceThreshold + confOffset)
        
        let wStillness = settings.useAutoSensitivity ? adaptiveEngine.weightStillness : 0.60
        let wPitch = settings.useAutoSensitivity ? adaptiveEngine.weightPitch : 0.40
        let wHR = settings.useAutoSensitivity ? adaptiveEngine.weightHR : 0.35
        
        // Apply granular micro-jitter threshold calibration
        let activeJitterThreshold = max(0.005, settings.stillnessThreshold + (settings.useAutoSensitivity ? adaptiveEngine.microJitterThresholdOffset : 0.0))
        let isMicroStill = motionManager.forceSimulatedStillness || (motionManager.movementScore < activeJitterThreshold)
        
        // 1. Micro-Jitter Stillness
        let stillnessCondition = isMicroStill && motionManager.stillDuration >= requiredStillnessSeconds
        wasStillnessActive = stillnessCondition
        if stillnessCondition {
            score += wStillness
            reasons.append("Stillness \(String(format: "%.1f", motionManager.stillDuration))s (+\(String(format: "%.2f", wStillness)))")
        }
        
        // 2. Posture Pitch Drop / Tilt
        let pitchCondition = motionManager.isPitchDropDetected
        wasPitchActive = pitchCondition
        if pitchCondition {
            score += wPitch
            reasons.append("Pitch Tilt (+\(String(format: "%.2f", wPitch)))")
        }
        
        // 3. Heart Rate Drop
        let hrCondition = healthKitManager.heartRateDropPercentage >= 0.04
        wasHRActive = hrCondition
        if hrCondition {
            score += wHR
            reasons.append("HR Drop \(Int(healthKitManager.heartRateDropPercentage * 100))% (+\(String(format: "%.2f", wHR)))")
        }
        
        totalConfidence = min(1.0, score)
        detectionReason = reasons.joined(separator: " | ")
        
        let thresholdMet = totalConfidence >= activeThreshold
        
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
        wasStillnessActive = false
        wasPitchActive = false
        wasHRActive = false
        confidenceStartTime = nil
    }
}
