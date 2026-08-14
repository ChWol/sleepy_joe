import Foundation
import WatchKit
import CoreML

/// Handles background consolidation training when the Apple Watch is charging.
/// Uses WKApplicationRefreshBackgroundTask to schedule deeper (50-epoch) training sessions
/// during idle charging periods for improved model convergence.
class BackgroundTrainingScheduler {
    
    // MARK: - Battery Check
    
    /// Returns true if the Watch is currently charging with sufficient battery (>50%)
    static func shouldRunConsolidation() -> Bool {
        let device = WKInterfaceDevice.current()
        let previousState = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        
        let batteryLevel = device.batteryLevel
        let batteryState = device.batteryState
        
        device.isBatteryMonitoringEnabled = previousState
        
        // batteryLevel < 0 means unknown (e.g., simulator) — allow training
        return (batteryState == .charging || batteryState == .full) && (batteryLevel > 0.50 || batteryLevel < 0)
    }
    
    // MARK: - Scheduling
    
    /// Schedule a background refresh task for 1 hour from now
    func scheduleConsolidation() {
        let nextFireDate = Date().addingTimeInterval(3600)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: nextFireDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("[BackgroundTraining] Error scheduling consolidation: \(error)")
            } else {
                print("[BackgroundTraining] Successfully scheduled consolidation for \(nextFireDate)")
            }
        }
    }
    
    // MARK: - Background Task Handler
    
    /// Handle a background refresh task by running deep consolidation training
    @MainActor
    func handleBackgroundTask(
        task: WKApplicationRefreshBackgroundTask,
        trainer: OnDeviceTrainer,
        buffer: MLReplayBuffer,
        classifier: SleepMLClassifier
    ) {
        // Only train if Watch is charging and has sufficient battery
        guard BackgroundTrainingScheduler.shouldRunConsolidation() else {
            print("[BackgroundTraining] Skipping — not charging or low battery")
            task.setTaskCompletedWithSnapshot(false)
            return
        }
        
        guard let modelURL = trainer.getCompiledModelURL() else {
            print("[BackgroundTraining] Skipping — no compiled model found")
            task.setTaskCompletedWithSnapshot(false)
            return
        }
        
        let userSamples = buffer.allSamples()
        let anchorSamples = AnchorSampleLoader.loadAnchorSamples()
        
        guard !userSamples.isEmpty else {
            print("[BackgroundTraining] Skipping — no user samples collected yet")
            task.setTaskCompletedWithSnapshot(false)
            return
        }
        
        print("[BackgroundTraining] Starting 50-epoch consolidation with \(userSamples.count) user + \(anchorSamples.count) anchor samples")
        
        // Deep consolidation training (50 epochs vs 15 for instant)
        trainer.train(
            compiledModelURL: modelURL,
            samples: userSamples,
            anchorSamples: anchorSamples,
            epochs: 50
        ) { success in
            if success {
                print("[BackgroundTraining] Consolidation training completed successfully")
                Task { @MainActor in
                    classifier.reloadModel()
                }
            } else {
                print("[BackgroundTraining] Consolidation training failed")
            }
            task.setTaskCompletedWithSnapshot(false)
        }
        
        // Schedule next consolidation
        scheduleConsolidation()
    }
}

// MARK: - Anchor Sample Loader

/// Loads the immutable gold-standard anchor samples from the app bundle
struct AnchorSampleLoader {
    
    /// Loads 20 anchor samples (10 awake + 10 sleep) from anchor_samples.json in the bundle
    static func loadAnchorSamples() -> [LabeledFeatureVector] {
        guard let url = Bundle.main.url(forResource: "anchor_samples", withExtension: "json") else {
            print("[AnchorSampleLoader] Warning: anchor_samples.json not found in bundle")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            // Anchor JSON uses a simpler format: [{label, features}]
            struct AnchorEntry: Codable {
                let label: String
                let features: [Float]
            }
            
            let anchorEntries = try JSONDecoder().decode([AnchorEntry].self, from: data)
            
            return anchorEntries.map { entry in
                LabeledFeatureVector(
                    id: UUID(),
                    timestamp: Date.distantPast, // Anchors are timeless
                    label: entry.label,
                    features: entry.features
                )
            }
        } catch {
            print("[AnchorSampleLoader] Error loading anchor samples: \(error)")
            return []
        }
    }
}
