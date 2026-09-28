import Foundation

// Host-side replay adapter for the production SleepDetectionEngine.
@MainActor final class MotionManager {
    var isTracking = true
    var lastSampleDate: Date?
    var rawAccelXHistory: [Float] = []
    var rawAccelYHistory: [Float] = []
    var rawAccelZHistory: [Float] = []
    var pitchDegreesHistory: [Double] = []
    var recentMovementScore = 0.0
    var movementScore = 0.0
    var forceSimulatedStillness = false
    var isPitchDropDetected = false
}

@MainActor final class HealthKitManager {
    var hasFreshHeartRate = false
    var hasRecentHeartRateDrop = false
    var heartRateDropPercentage = 0.0
}

struct SessionSettings {
    let useAutoSensitivity = false
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

private struct ReplayFile: Decodable {
    let formatVersion: Int
    let sessions: [ReplaySession]
}

private struct ReplaySession: Decodable {
    let id: String
    let frames: [ReplayFrame]
}

private struct ReplayFrame: Decodable {
    let seconds: Double
    let x: Float
    let y: Float
    let z: Float
    let pitchDegrees: Double
    let heartRateDropPercentage: Double?
    let truth: String // "awake" or "sleep"
}

private struct SessionMetrics: Encodable {
    let id: String
    let durationSeconds: Double
    let sleepOnsets: Int
    let detectedOnsets: Int
    let missedOnsets: Int
    let falseAlerts: Int
    let alertLatenciesSeconds: [Double]
    let dataGaps: Int
}

private struct Evaluation: Encodable {
    let formatVersion: Int
    let sessions: [SessionMetrics]
    let totalSleepOnsets: Int
    let detectedOnsets: Int
    let missedOnsets: Int
    let falseAlerts: Int
    let falseAlertsPerHour: Double
    let sensitivity: Double
    let medianLatencySeconds: Double?
    let dataGaps: Int
}

@main struct ReplayEvaluator {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: evaluate-sensor-replays <replay.json>\n", stderr)
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let replay = try JSONDecoder().decode(ReplayFile.self, from: Data(contentsOf: url))
        guard replay.formatVersion == 1 else {
            fputs("Unsupported replay formatVersion: \(replay.formatVersion)\n", stderr)
            exit(2)
        }
        guard replay.sessions.allSatisfy({ session in
            !session.frames.isEmpty && session.frames.allSatisfy {
                ($0.truth == "awake" || $0.truth == "sleep") &&
                $0.seconds.isFinite && $0.x.isFinite && $0.y.isFinite && $0.z.isFinite &&
                $0.pitchDegrees.isFinite &&
                ($0.heartRateDropPercentage?.isFinite ?? true)
            }
        }) else {
            fputs("Replay contains empty sessions, invalid labels, or non-finite sensor values\n", stderr)
            exit(2)
        }

        let metrics = replay.sessions.map(evaluate)
        let totalSleep = metrics.reduce(0) { $0 + $1.sleepOnsets }
        let detected = metrics.reduce(0) { $0 + $1.detectedOnsets }
        let missed = metrics.reduce(0) { $0 + $1.missedOnsets }
        let falseAlerts = metrics.reduce(0) { $0 + $1.falseAlerts }
        let hours = metrics.reduce(0.0) { $0 + $1.durationSeconds } / 3600
        let latencies = metrics.flatMap(\.alertLatenciesSeconds).sorted()
        let median: Double? = latencies.isEmpty ? nil : latencies[latencies.count / 2]
        let report = Evaluation(
            formatVersion: replay.formatVersion,
            sessions: metrics,
            totalSleepOnsets: totalSleep,
            detectedOnsets: detected,
            missedOnsets: missed,
            falseAlerts: falseAlerts,
            falseAlertsPerHour: hours > 0 ? Double(falseAlerts) / hours : 0,
            sensitivity: totalSleep > 0 ? Double(detected) / Double(totalSleep) : 0,
            medianLatencySeconds: median,
            dataGaps: metrics.reduce(0) { $0 + $1.dataGaps }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    }

    @MainActor private static func evaluate(_ session: ReplaySession) -> SessionMetrics {
        let origin = Date(timeIntervalSince1970: 0)
        let motion = MotionManager()
        let health = HealthKitManager()
        let engine = SleepDetectionEngine()
        let settings = SessionSettings()
        let adaptive = AdaptiveLearningEngine()
        var priorAcceleration: (Float, Float, Float)?
        var recentDeltas: [Double] = []
        var priorPitch: Double?
        var pitchDropExpiry: Double?
        var pitchResetExpiry: Double?
        let frames = session.frames.sorted(by: { $0.seconds < $1.seconds })
        var previousTruth = "awake"
        var onsetQueue: [Double] = []
        var latencies: [Double] = []
        var falseAlerts = 0
        var dataGaps = 0
        var previousTime: Double?
        var wasDetected = false

        for frame in frames {
            if let previousTime, frame.seconds - previousTime > 0.25 { dataGaps += 1 }
            previousTime = frame.seconds
            motion.lastSampleDate = origin.addingTimeInterval(frame.seconds)
            motion.rawAccelXHistory.append(frame.x)
            motion.rawAccelYHistory.append(frame.y)
            motion.rawAccelZHistory.append(frame.z)
            motion.pitchDegreesHistory.append(frame.pitchDegrees)
            if motion.rawAccelXHistory.count > 50 {
                motion.rawAccelXHistory.removeFirst()
                motion.rawAccelYHistory.removeFirst()
                motion.rawAccelZHistory.removeFirst()
                motion.pitchDegreesHistory.removeFirst()
            }
            if let previous = priorAcceleration {
                let dx = frame.x - previous.0
                let dy = frame.y - previous.1
                let dz = frame.z - previous.2
                let delta = sqrt(Double(dx * dx + dy * dy + dz * dz))
                recentDeltas.append(delta)
                if recentDeltas.count > 10 { recentDeltas.removeFirst() }
                motion.recentMovementScore = recentDeltas.reduce(0, +) / Double(recentDeltas.count)
                motion.movementScore = motion.recentMovementScore
            }
            priorAcceleration = (frame.x, frame.y, frame.z)
            let pitchRise = frame.pitchDegrees - (priorPitch ?? frame.pitchDegrees)
            priorPitch = frame.pitchDegrees
            if pitchRise > 8 {
                pitchDropExpiry = nil
                pitchResetExpiry = frame.seconds + 5
            }
            if motion.pitchDegreesHistory.count >= 20 {
                let initial = motion.pitchDegreesHistory.prefix(10).reduce(0, +) / 10
                let current = motion.pitchDegreesHistory.suffix(10).reduce(0, +) / 10
                if initial - current > 12 && (pitchResetExpiry.map { $0 < frame.seconds } ?? true) {
                    pitchDropExpiry = frame.seconds + 8
                }
            }
            motion.isPitchDropDetected = pitchDropExpiry.map { $0 > frame.seconds } ?? false
            health.heartRateDropPercentage = frame.heartRateDropPercentage ?? 0
            health.hasFreshHeartRate = frame.heartRateDropPercentage != nil
            health.hasRecentHeartRateDrop = health.hasFreshHeartRate && health.heartRateDropPercentage >= 0.05

            if frame.truth == "sleep" && previousTruth != "sleep" { onsetQueue.append(frame.seconds) }
            previousTruth = frame.truth

            engine.evaluate(
                motionManager: motion,
                healthKitManager: health,
                settings: settings,
                adaptiveEngine: adaptive,
                feedbackSamples: [],
                at: motion.lastSampleDate!
            )
            if engine.isSleepDetected && !wasDetected {
                if let onsetIndex = onsetQueue.firstIndex(where: { frame.seconds >= $0 && frame.seconds - $0 <= 30 }) {
                    latencies.append(frame.seconds - onsetQueue.remove(at: onsetIndex))
                } else {
                    falseAlerts += 1
                }
            }
            wasDetected = engine.isSleepDetected
        }

        let onsetTimes = frames.enumerated().compactMap { index, frame -> Double? in
            guard frame.truth == "sleep", index == 0 || frames[index - 1].truth != "sleep" else { return nil }
            return frame.seconds
        }
        let detectedOnsets = latencies.count
        return SessionMetrics(
            id: session.id,
            durationSeconds: max(0, (frames.last?.seconds ?? 0) - (frames.first?.seconds ?? 0)),
            sleepOnsets: onsetTimes.count,
            detectedOnsets: detectedOnsets,
            missedOnsets: max(0, onsetTimes.count - detectedOnsets),
            falseAlerts: falseAlerts,
            alertLatenciesSeconds: latencies,
            dataGaps: dataGaps
        )
    }
}
