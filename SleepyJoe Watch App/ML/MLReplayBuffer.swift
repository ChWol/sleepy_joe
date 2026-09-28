import Foundation
import Combine

// MARK: - Labeled Feature Vector
/// A labeled entry containing 16 motion features
struct LabeledFeatureVector: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let label: String // "sleep" or "awake"
    let features: [Float] // 16 features
}

// MARK: - ML Replay Buffer
/// A ring buffer for machine learning feature vectors, stored to disk.
@MainActor
class MLReplayBuffer: ObservableObject {
    @Published var entries: [LabeledFeatureVector] = []
    @Published var sleepCount: Int = 0
    @Published var awakeCount: Int = 0
    
    private let maxCapacity = 100
    private let fileURL: URL
    
    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documentsDirectory.appendingPathComponent("ml_replay_buffer.json")
        loadFromDisk()
    }
    
    /// Adds a new feature sample to the replay buffer, managing capacity and persistence.
    /// - Parameters:
    ///   - label: The truth label ("sleep" or "awake")
    ///   - features: The array of 16 feature floats.
    func addSample(label: String, features: [Float]) {
        guard (label == "sleep" || label == "awake"),
              features.count == 16,
              features.allSatisfy(\.isFinite) else { return }
        let newEntry = LabeledFeatureVector(
            id: UUID(),
            timestamp: Date(),
            label: label,
            features: features
        )
        
        entries.append(newEntry)
        
        // Preserve scarce confirmed positives when the user reports many false
        // alarms. Keep enough negatives to represent several desk postures.
        let classLimit = label == "sleep" ? 40 : 60
        if entries.filter({ $0.label == label }).count > classLimit,
           let oldestSameClass = entries.firstIndex(where: { $0.label == label }) {
            entries.remove(at: oldestSameClass)
        }

        if entries.count > maxCapacity {
            entries.removeFirst()
        }
        updateCounts()
        saveToDisk()
    }
    
    /// Loads the stored samples from the Documents directory JSON.
    func loadFromDisk() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([LabeledFeatureVector].self, from: data)
            
            // Reassign to published property
            let valid = decoded.filter {
                ($0.label == "sleep" || $0.label == "awake") &&
                $0.features.count == 16 && $0.features.allSatisfy(\.isFinite)
            }
            let positives = valid.filter { $0.label == "sleep" }.suffix(40)
            let negatives = valid.filter { $0.label == "awake" }.suffix(60)
            self.entries = (positives + negatives).sorted { $0.timestamp < $1.timestamp }
            
            // Recompute counts
            updateCounts()
        } catch {
            print("Failed to load replay buffer: \(error.localizedDescription)")
            // Fallback to empty
            entries = []
            updateCounts()
        }
    }
    
    /// Clears the entire buffer both in-memory and on-disk.
    func clear() {
        entries = []
        updateCounts()
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to delete replay buffer file: \(error.localizedDescription)")
        }
    }
    
    /// Returns all available samples in the buffer.
    func allSamples() -> [LabeledFeatureVector] {
        return entries
    }
    
    // MARK: - Private Helpers
    
    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save replay buffer: \(error.localizedDescription)")
        }
    }
    
    private func updateCounts() {
        sleepCount = entries.filter { $0.label == "sleep" }.count
        awakeCount = entries.filter { $0.label == "awake" }.count
    }
}
