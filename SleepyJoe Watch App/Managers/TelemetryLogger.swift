import Foundation

/// Sensor window frozen when the alarm was triggered and labeled upon feedback.
struct TelemetrySample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let label: String // "true_positive" (✓) or "false_positive" (✕)
    let sampleRateHz: Int // 10Hz
    let windowDurationSeconds: Double // 5.0s
    let pitchDegrees: [Double]
    let movementDeltas: [Double]
    let accelerationX: [Float]?
    let accelerationY: [Float]?
    let accelerationZ: [Float]?
    let heartRate: Double
    let heartRateDropPercentage: Double
    
    init(
        label: String,
        timestamp: Date,
        pitchBuffer: [Double],
        motionBuffer: [Double],
        accelerationX: [Float],
        accelerationY: [Float],
        accelerationZ: [Float],
        heartRate: Double,
        hrDrop: Double
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.label = label
        self.sampleRateHz = 10
        self.windowDurationSeconds = Double(min(50, pitchBuffer.count)) / 10.0
        // Capture the most recent complete window available at the alert.
        self.pitchDegrees = Array(pitchBuffer.suffix(50))
        self.movementDeltas = Array(motionBuffer.suffix(50))
        self.accelerationX = Array(accelerationX.suffix(50))
        self.accelerationY = Array(accelerationY.suffix(50))
        self.accelerationZ = Array(accelerationZ.suffix(50))
        self.heartRate = heartRate
        self.heartRateDropPercentage = hrDrop
    }
}

/// Low-volume, raw-signal-free diagnostic event. Saved only when the user opts in.
struct DetectionDecisionTrace: Codable {
    let timestamp: Date
    let event: String
    let reason: String
    let confidence: Double
    let confidenceThreshold: Double
    let stillnessThreshold: Double
    let requiredStillnessSeconds: Double
    let stillnessDuration: TimeInterval
    let movementScore: Double
    let pitchCue: Bool
    let heartRateCue: Bool
    let motionSampleAge: TimeInterval?
}

/// On-Device Telemetry Logger for collecting clean 5-second labeled dataset samples.
@MainActor
final class TelemetryLogger: ObservableObject {
    
    @Published var totalSavedSamples: Int = 0
    @Published private(set) var totalDecisionTraceEntries: Int = 0
    @Published private(set) var diagnosticsEnabled: Bool
    
    private let telemetryFolder: URL
    private let diagnosticsURL: URL
    private static let diagnosticsPreferenceKey = "focus_save_decision_diagnostics"
    private let maximumLabeledWindows = 1_000
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let telemetryFolder = docs.appendingPathComponent("telemetry", isDirectory: true)
        self.telemetryFolder = telemetryFolder
        self.diagnosticsURL = telemetryFolder.appendingPathComponent("decision_traces.jsonl")
        self.diagnosticsEnabled = UserDefaults.standard.bool(forKey: Self.diagnosticsPreferenceKey)
        
        try? FileManager.default.createDirectory(at: telemetryFolder, withIntermediateDirectories: true)
        var localOnlyFolder = telemetryFolder
        var folderValues = URLResourceValues()
        folderValues.isExcludedFromBackup = true
        try? localOnlyFolder.setResourceValues(folderValues)
        updateSampleCount()
        updateDecisionTraceCount()
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.diagnosticsPreferenceKey)
    }

    func recordDecision(_ trace: DetectionDecisionTrace) {
        guard diagnosticsEnabled,
              let encoded = try? JSONEncoder().encode(trace) else { return }
        var line = encoded
        line.append(0x0A)
        do {
            if FileManager.default.fileExists(atPath: diagnosticsURL.path) {
                let handle = try FileHandle(forWritingTo: diagnosticsURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: diagnosticsURL, options: .atomic)
            }
            totalDecisionTraceEntries += 1
            if totalDecisionTraceEntries > 5_000 { trimDecisionTraceFile() }
        } catch {
            print("[TelemetryLogger] Could not save decision trace: \(error)")
        }
    }
    
    /// Save an alert-time window when the user explicitly labels the event.
    func recordSample(
        label: String,
        timestamp: Date,
        pitchBuffer: [Double],
        motionBuffer: [Double],
        accelerationX: [Float],
        accelerationY: [Float],
        accelerationZ: [Float],
        heartRate: Double,
        hrDrop: Double
    ) {
        let sample = TelemetrySample(
            label: label,
            timestamp: timestamp,
            pitchBuffer: pitchBuffer,
            motionBuffer: motionBuffer,
            accelerationX: accelerationX,
            accelerationY: accelerationY,
            accelerationZ: accelerationZ,
            heartRate: heartRate,
            hrDrop: hrDrop
        )
        
        let filename = "sample_\(sample.id.uuidString).json"
        let fileURL = telemetryFolder.appendingPathComponent(filename)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(sample) {
            do {
                try data.write(to: fileURL, options: .atomic)
                totalSavedSamples += 1
                trimLabeledWindowsIfNeeded()
            } catch {
                print("[TelemetryLogger] Could not save sample: \(error)")
            }
        }
    }
    
    /// Clear all recorded telemetry samples
    func clearTelemetry() {
        if let files = try? FileManager.default.contentsOfDirectory(at: telemetryFolder, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        updateSampleCount()
        totalDecisionTraceEntries = 0
    }
    
    private func updateSampleCount() {
        if let files = try? FileManager.default.contentsOfDirectory(at: telemetryFolder, includingPropertiesForKeys: nil) {
            totalSavedSamples = files.filter { $0.pathExtension == "json" }.count
        } else {
            totalSavedSamples = 0
        }
    }

    private func trimLabeledWindowsIfNeeded() {
        guard totalSavedSamples > maximumLabeledWindows,
              let files = try? FileManager.default.contentsOfDirectory(
                at: telemetryFolder,
                includingPropertiesForKeys: [.creationDateKey]
              ) else { return }
        let samples = files.filter { $0.pathExtension == "json" }
        let oldestFirst = samples.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate < rightDate
        }
        for file in oldestFirst.prefix(max(0, oldestFirst.count - maximumLabeledWindows)) {
            try? FileManager.default.removeItem(at: file)
        }
        updateSampleCount()
    }

    private func updateDecisionTraceCount() {
        guard let data = try? Data(contentsOf: diagnosticsURL) else {
            totalDecisionTraceEntries = 0
            return
        }
        totalDecisionTraceEntries = data.split(separator: 0x0A).count
    }

    private func trimDecisionTraceFile() {
        guard let data = try? Data(contentsOf: diagnosticsURL) else { return }
        let lines = data.split(separator: 0x0A).suffix(5_000)
        var trimmed = Data()
        for line in lines {
            trimmed.append(contentsOf: line)
            trimmed.append(0x0A)
        }
        do {
            try trimmed.write(to: diagnosticsURL, options: .atomic)
            totalDecisionTraceEntries = lines.count
        } catch {
            print("[TelemetryLogger] Could not trim decision trace: \(error)")
        }
    }
}
