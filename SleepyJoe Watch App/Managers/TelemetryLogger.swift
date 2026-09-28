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

/// On-Device Telemetry Logger for collecting clean 5-second labeled dataset samples.
@MainActor
final class TelemetryLogger: ObservableObject {
    
    @Published var totalSavedSamples: Int = 0
    
    private let telemetryFolder: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.telemetryFolder = docs.appendingPathComponent("telemetry", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: telemetryFolder, withIntermediateDirectories: true)
        updateSampleCount()
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
    }
    
    private func updateSampleCount() {
        if let files = try? FileManager.default.contentsOfDirectory(at: telemetryFolder, includingPropertiesForKeys: nil) {
            totalSavedSamples = files.filter { $0.pathExtension == "json" }.count
        } else {
            totalSavedSamples = 0
        }
    }
}
