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
        let newEntry = LabeledFeatureVector(
            id: UUID(),
            timestamp: Date(),
            label: label,
            features: features
        )
        
        entries.append(newEntry)
        
        // Evict oldest if we exceed capacity
        if entries.count > maxCapacity {
            let removed = entries.removeFirst()
            if removed.label == "sleep" {
                sleepCount -= 1
            } else if removed.label == "awake" {
                awakeCount -= 1
            }
        }
        
        if label == "sleep" {
            sleepCount += 1
        } else if label == "awake" {
            awakeCount += 1
        }
        
        saveToDisk()
    }
    
    /// Loads the stored samples from the Documents directory JSON.
    func loadFromDisk() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([LabeledFeatureVector].self, from: data)
            
            // Reassign to published property
            self.entries = decoded
            
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
            // Optional: for better debuggability on device
            encoder.outputFormatting = .prettyPrinted
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
