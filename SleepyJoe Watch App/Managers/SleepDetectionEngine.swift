import Foundation
import Combine

/// Combines current sensor evidence. An unvalidated model must never turn a
/// quiet desk posture into a sleep alarm or veto a strong physical cue.
@MainActor
final class SleepDetectionEngine: ObservableObject {
    @Published var totalConfidence: Double = 0
    @Published var isSleepDetected = false
    @Published var detectionReason = ""
    @Published var wasStillnessActive = false
    @Published var wasPitchActive = false
    @Published var wasHRActive = false
    @Published var mlConfidence: Double = 0
    @Published var ruleConfidence: Double = 0
    @Published var isWarningCandidate = false

    var lastExtractedFeatures: [Float] = []
    private var stillnessStartTime: Date?
    private var confidenceStartTime: Date?

    func evaluate(
        motionManager: MotionManager,
        healthKitManager: HealthKitManager,
        settings: SessionSettings,
        adaptiveEngine: AdaptiveLearningEngine,
        feedbackSamples: [LabeledFeatureVector],
        at now: Date = Date()
    ) {
        guard motionManager.isTracking,
              let lastSample = motionManager.lastSampleDate,
              now.timeIntervalSince(lastSample) < 1.0,
              motionManager.rawAccelXHistory.count >= 10 else {
            resetEvidence()
            return
        }

        let durationOffset = settings.useAutoSensitivity ? adaptiveEngine.personalStillnessOffset : 0
        let requiredStillness = max(1, settings.stillnessRequiredSeconds + durationOffset)
        let jitterOffset = settings.useAutoSensitivity ? adaptiveEngine.microJitterThresholdOffset : 0
        let motionThreshold = max(0.008, settings.stillnessThreshold + jitterOffset)

        // A five-second average hides conscious corrections at the transition.
        let isQuiet = motionManager.forceSimulatedStillness || motionManager.recentMovementScore < motionThreshold
        if isQuiet {
            if stillnessStartTime == nil { stillnessStartTime = now }
        } else {
            stillnessStartTime = nil
        }
        let stillnessDuration = stillnessStartTime.map { now.timeIntervalSince($0) } ?? 0
        let stillness = isQuiet && stillnessDuration >= requiredStillness
        let pitch = stillness && motionManager.isPitchDropDetected
        let hr = stillness && healthKitManager.hasRecentHeartRateDrop && healthKitManager.heartRateDropPercentage >= 0.05
        wasStillnessActive = stillness
        wasPitchActive = pitch
        wasHRActive = hr

        let stillnessWeight = settings.useAutoSensitivity ? adaptiveEngine.weightStillness : 0.60
        let pitchWeight = settings.useAutoSensitivity ? adaptiveEngine.weightPitch : 0.40
        let hrWeight = settings.useAutoSensitivity ? adaptiveEngine.weightHR : 0.35
        let score = (stillness ? stillnessWeight : 0) + (pitch ? pitchWeight : 0) + (hr ? hrWeight : 0)
        ruleConfidence = min(1, score)
        mlConfidence = 0
        lastExtractedFeatures = []

        // Personal hard negatives guard ambiguous patterns. They cannot block
        // a posture drop, and an overlapping confirmed positive cancels the veto.
        var resemblesKnownAwakePattern = false
        if stillness && motionManager.rawAccelXHistory.count == 50 {
            let features = FeatureExtractor.extractFeatures(
                x: motionManager.rawAccelXHistory,
                y: motionManager.rawAccelYHistory,
                z: motionManager.rawAccelZHistory,
                pitch: motionManager.pitchDegreesHistory.map(Float.init)
            )
            lastExtractedFeatures = features
            resemblesKnownAwakePattern = PersonalPatternMatcher.isKnownAwake(features, samples: feedbackSamples)
        }

        // Quiet focused work is common. Require another cue, or a longer and
        // exceptionally quiet interval. Confirmed false alarms can suppress
        // that ambiguous path and isolated heart-rate changes.
        let veryStill = motionManager.forceSimulatedStillness ||
            (motionManager.recentMovementScore < min(0.018, motionThreshold * 0.45) &&
             motionManager.movementScore < min(0.015, motionThreshold * 0.35))
        let sustainedStillness = stillnessDuration >= max(10, requiredStillness + 5) && veryStill
        let hasEvidence = stillness && (pitch || (hr && !resemblesKnownAwakePattern) ||
            (sustainedStillness && !resemblesKnownAwakePattern))
        isWarningCandidate = hasEvidence ||
            (stillness && veryStill && !resemblesKnownAwakePattern && !sustainedStillness)
        let confidenceOffset = settings.useAutoSensitivity ? adaptiveEngine.confidenceThresholdOffset : 0
        let threshold = max(0.35, settings.confidenceThreshold + confidenceOffset)
        totalConfidence = ruleConfidence
        detectionReason = [
            stillness ? "Still \(Int(stillnessDuration))s" : nil,
            pitch ? "Posture change" : nil,
            hr ? "Heart-rate trend" : nil,
            resemblesKnownAwakePattern ? "Known awake pattern" : nil
        ].compactMap { $0 }.joined(separator: " · ")

        if motionManager.rawAccelXHistory.count >= 30 &&
            hasEvidence && (score >= threshold || sustainedStillness) {
            if confidenceStartTime == nil { confidenceStartTime = now }
            isSleepDetected = confidenceStartTime.map { now.timeIntervalSince($0) >= 1 } ?? false
        } else {
            confidenceStartTime = nil
            isSleepDetected = false
        }
    }

    func reset() {
        stillnessStartTime = nil
        resetEvidence()
    }

    private func resetEvidence() {
        stillnessStartTime = nil
        totalConfidence = 0
        ruleConfidence = 0
        mlConfidence = 0
        isSleepDetected = false
        detectionReason = ""
        wasStillnessActive = false
        wasPitchActive = false
        wasHRActive = false
        isWarningCandidate = false
        confidenceStartTime = nil
        lastExtractedFeatures = []
    }
}

/// Conservative few-shot memory of labeled false alarms.
enum PersonalPatternMatcher {
    static func isKnownAwake(_ features: [Float], samples: [LabeledFeatureVector]) -> Bool {
        guard features.count == 16 else { return false }
        let closeAwake = samples.filter { $0.label == "awake" && distance(features, $0.features) < 0.75 }
        guard closeAwake.count >= 3 else { return false }
        return !samples.contains { $0.label == "sleep" && distance(features, $0.features) < 0.9 }
    }

    private static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard b.count == 16 else { return .infinity }
        let dimensions: [(Int, Float)] = [
            (3, 0.003), (4, 0.003), (5, 0.003), (7, 0.04),
            (8, 0.08), (9, 0.08), (10, 0.08), (11, 25),
            (12, 12), (13, 30), (14, 0.15), (15, 0.02)
        ]
        let squared = dimensions.reduce(Float(0)) { sum, item in
            let difference = (a[item.0] - b[item.0]) / item.1
            return sum + difference * difference
        }
        return sqrt(squared / Float(dimensions.count))
    }
}
