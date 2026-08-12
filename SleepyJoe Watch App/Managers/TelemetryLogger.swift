import Foundation

/// Telemetry sample representing a 5-second multivariate sensor window
/// retroactively captured and labeled upon user feedback.
struct TelemetrySample: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let label: String // "true_positive" (✓) or "false_positive" (✕)
    let sampleRateHz: Int // 10Hz
    let windowDurationSeconds: Double // 5.0s
    let pitchDegrees: [Double] // 50 timesteps
    let movementDeltas: [Double] // 50 timesteps
    let heartRate: Double
    let heartRateDropPercentage: Double
    
    init(
        label: String,
        pitchBuffer: [Double],
        motionBuffer: [Double],
        heartRate: Double,
        hrDrop: Double
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.label = label
        self.sampleRateHz = 10
        self.windowDurationSeconds = 5.0
        // Capture last 50 timesteps (5 seconds)
        self.pitchDegrees = Array(pitchBuffer.suffix(50))
        self.movementDeltas = Array(motionBuffer.suffix(50))
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
    
    /// Save a clean 5-second retroactively labeled sample upon ✓ or ✕ tap
    func recordSample(
        label: String,
        pitchBuffer: [Double],
        motionBuffer: [Double],
        heartRate: Double,
        hrDrop: Double
    ) {
        let sample = TelemetrySample(
            label: label,
            pitchBuffer: pitchBuffer,
            motionBuffer: motionBuffer,
            heartRate: heartRate,
            hrDrop: hrDrop
        )
        
        let filename = "sample_\(Int(sample.timestamp.timeIntervalSince1970))_\(sample.label).json"
        let fileURL = telemetryFolder.appendingPathComponent(filename)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(sample) {
            try? data.write(to: fileURL)
            updateSampleCount()
            print("💾 [TelemetryLogger] Saved 5s clean sample (\(sample.label)) to \(filename). Total: \(totalSavedSamples)")
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
