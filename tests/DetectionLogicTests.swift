import Foundation

// Host-side sensor doubles let this test the production detector without a watch.
@MainActor final class MotionManager {
    var isTracking = true
    var lastSampleDate: Date?
    var rawAccelXHistory = [Float](repeating: 0.002, count: 50)
    var rawAccelYHistory = [Float](repeating: 0.001, count: 50)
    var rawAccelZHistory = [Float](repeating: 0.001, count: 50)
    var pitchDegreesHistory = [Double](repeating: -20, count: 50)
    var recentMovementScore = 0.03
    var movementScore = 0.03
    var forceSimulatedStillness = false
    var isPitchDropDetected = false
}
@MainActor final class HealthKitManager {
    var hasFreshHeartRate = false
    var hasRecentHeartRateDrop = false
    var heartRateDropPercentage = 0.0
}
struct SessionSettings {
    let useAutoSensitivity = true
    let stillnessRequiredSeconds = 4.5
    let stillnessThreshold = 0.05
    let confidenceThreshold = 0.55
}
@MainActor final class AdaptiveLearningEngine {
    let personalStillnessOffset = 0.0
    let microJitterThresholdOffset = 0.0
    let weightStillness = 0.60
    let weightPitch = 0.40
    let weightHR = 0.35
    let confidenceThresholdOffset = 0.0
}
struct LabeledFeatureVector {
    let label: String
    let features: [Float]
}

@main struct DetectionLogicTests {
    @MainActor static func main() {
        let origin = Date()
        let motion = MotionManager()
        let health = HealthKitManager()
        let settings = SessionSettings()
        let adaptive = AdaptiveLearningEngine()
        let engine = SleepDetectionEngine()
        func evaluate(_ seconds: Double, samples: [LabeledFeatureVector] = []) {
            let now = origin.addingTimeInterval(seconds)
            motion.lastSampleDate = now
            engine.evaluate(motionManager: motion, healthKitManager: health,
                            settings: settings, adaptiveEngine: adaptive,
                            feedbackSamples: samples, at: now)
        }

        evaluate(0)
        evaluate(5)
        evaluate(14)
        precondition(!engine.isSleepDetected, "ordinary quiet desk work must not alert")
        motion.lastSampleDate = origin
        engine.evaluate(motionManager: motion, healthKitManager: health,
                        settings: settings, adaptiveEngine: adaptive,
                        feedbackSamples: [], at: origin.addingTimeInterval(20))
        precondition(!engine.isSleepDetected, "stale motion must not alert")

        engine.reset()
        health.hasFreshHeartRate = true
        health.hasRecentHeartRateDrop = true
        health.heartRateDropPercentage = 0.06
        evaluate(30)
        evaluate(35)
        evaluate(36.1)
        precondition(engine.isSleepDetected, "fresh heart-rate trend plus stillness should alert")

        let features = FeatureExtractor.extractFeatures(
            x: motion.rawAccelXHistory, y: motion.rawAccelYHistory,
            z: motion.rawAccelZHistory, pitch: motion.pitchDegreesHistory.map(Float.init))
        let negatives = (0..<3).map { _ in LabeledFeatureVector(label: "awake", features: features) }
        precondition(PersonalPatternMatcher.isKnownAwake(features, samples: negatives))
        let positive = LabeledFeatureVector(label: "sleep", features: features)
        precondition(!PersonalPatternMatcher.isKnownAwake(features, samples: negatives + [positive]),
                     "a confirmed positive protects a similar pattern")

        var invalidFeatures = features
        invalidFeatures[3] = .nan
        let invalidNegative = LabeledFeatureVector(label: "awake", features: invalidFeatures)
        precondition(!PersonalPatternMatcher.isKnownAwake(features, samples: [negatives[0], negatives[1], invalidNegative]),
                     "invalid feature samples must not count toward a false-alarm veto")
        precondition(!PersonalPatternMatcher.isKnownAwake(invalidFeatures, samples: negatives),
                     "non-finite live features must not activate a false-alarm veto")

        engine.reset()
        evaluate(50, samples: negatives)
        evaluate(55, samples: negatives)
        evaluate(56.1, samples: negatives)
        precondition(!engine.isSleepDetected, "repeated false alarms should block ambiguous HR cues")
        motion.isPitchDropDetected = true
        evaluate(57, samples: negatives)
        evaluate(58.1, samples: negatives)
        precondition(engine.isSleepDetected, "hard negatives must not block a posture drop")

        engine.reset()
        motion.isPitchDropDetected = false
        motion.recentMovementScore = 0.005
        motion.movementScore = 0.005
        health.hasRecentHeartRateDrop = false
        evaluate(70)
        evaluate(81)
        evaluate(82.1)
        precondition(engine.isSleepDetected, "very long exceptional stillness remains a motion-only fallback")

        let f = FeatureExtractor.extractFeatures(
            x: [Float(1), 2], y: [Float(0), 0], z: [Float(0), 0], pitch: [Float(0), 0])
        precondition(abs(f[6] - (0.25 / 3)) < 0.00001, "total jitter is mean variance")
        print("Detection logic checks passed")
    }
}
