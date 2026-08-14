import Foundation
import CoreML

/// Orchestrates on-device model training via CoreML's MLUpdateTask.
/// Handles batch construction, class balancing, and atomic model persistence.
class OnDeviceTrainer {
    
    /// Returns the URL of the current compiled model (user-trained if exists, bundle fallback)
    func getCompiledModelURL() -> URL? {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let userTrainedModelURL = documentsURL.appendingPathComponent("SleepyClassifier.mlmodelc")
        
        if fileManager.fileExists(atPath: userTrainedModelURL.path) {
            return userTrainedModelURL
        } else {
            return Bundle.main.url(forResource: "SleepyClassifier", withExtension: "mlmodelc")
        }
    }
    
    /// Trains the model on-device with combined anchor + user samples.
    /// Sleep samples are duplicated ×3 for class balance.
    /// Runs on a background queue (.utility QoS) to avoid UI lag.
    func train(
        compiledModelURL: URL,
        samples: [LabeledFeatureVector],
        anchorSamples: [LabeledFeatureVector],
        epochs: Int,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            // Combine anchor samples with user samples
            var combinedSamples = anchorSamples + samples
            
            // Duplicate sleep samples ×3 for class balance
            let sleepSamples = combinedSamples.filter { $0.label == "sleep" }
            combinedSamples.append(contentsOf: sleepSamples) // ×2
            combinedSamples.append(contentsOf: sleepSamples) // ×3
            
            // Build MLBatchProvider
            var featureProviders: [MLFeatureProvider] = []
            
            for sample in combinedSamples {
                guard sample.features.count == 16 else { continue }
                do {
                    let multiArray = try MLMultiArray(shape: [16], dataType: .float32)
                    for (index, value) in sample.features.enumerated() {
                        multiArray[index] = NSNumber(value: value)
                    }
                    let provider = try MLDictionaryFeatureProvider(dictionary: [
                        "features": multiArray,
                        "classLabel": sample.label
                    ])
                    featureProviders.append(provider)
                } catch {
                    print("[OnDeviceTrainer] Error creating feature provider: \(error)")
                }
            }
            
            guard !featureProviders.isEmpty else {
                print("[OnDeviceTrainer] No valid feature providers — skipping training")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let batchProvider = MLArrayBatchProvider(array: featureProviders)
            
            // Configure training
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            
            do {
                let progressHandlers = MLUpdateProgressHandlers(
                    forEvents: [.trainingBegin, .epochEnd],
                    progressHandler: { context in
                        if let epoch = context.metrics[.epochIndex] as? Int,
                           let loss = context.metrics[.lossValue] as? Double {
                            print("[OnDeviceTrainer] Epoch \(epoch) — Loss: \(String(format: "%.4f", loss))")
                        }
                    },
                    completionHandler: { context in
                        let fileManager = FileManager.default
                        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let updatedModelURL = documentsURL.appendingPathComponent("SleepyClassifier.mlmodelc")
                        
                        do {
                            // Write to temp location first
                            let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mlmodelc")
                            try context.model.write(to: tempURL)
                            
                            // Atomic swap
                            if fileManager.fileExists(atPath: updatedModelURL.path) {
                                _ = try fileManager.replaceItemAt(updatedModelURL, withItemAt: tempURL)
                            } else {
                                try fileManager.moveItem(at: tempURL, to: updatedModelURL)
                            }
                            
                            print("[OnDeviceTrainer] Model saved successfully to \(updatedModelURL.lastPathComponent)")
                            DispatchQueue.main.async { completion(true) }
                        } catch {
                            print("[OnDeviceTrainer] Error saving updated model: \(error)")
                            DispatchQueue.main.async { completion(false) }
                        }
                    }
                )
                
                let updateTask = try MLUpdateTask(
                    forModelAt: compiledModelURL,
                    trainingData: batchProvider,
                    configuration: config,
                    progressHandlers: progressHandlers
                )
                
                updateTask.resume()
            } catch {
                print("[OnDeviceTrainer] Error setting up MLUpdateTask: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}
