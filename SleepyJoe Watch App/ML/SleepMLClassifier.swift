import Foundation
import CoreML

@MainActor
class SleepMLClassifier: ObservableObject {
    @Published var sleepProbability: Double = 0.0
    @Published var isModelReady: Bool = false
    
    private var model: MLModel?
    
    init() {
        loadModel()
    }
    
    private func getModelURL() -> URL? {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let userTrainedModelURL = documentsURL.appendingPathComponent("SleepyClassifier.mlmodelc")
        
        if fileManager.fileExists(atPath: userTrainedModelURL.path) {
            return userTrainedModelURL
        } else {
            guard let bundleURL = Bundle.main.url(forResource: "SleepyClassifier", withExtension: "mlmodelc") else {
                print("Error: Could not find SleepyClassifier.mlmodelc in bundle.")
                return nil
            }
            return bundleURL
        }
    }
    
    private func loadModel() {
        guard let url = getModelURL() else { return }
        
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            self.model = try MLModel(contentsOf: url, configuration: configuration)
            self.isModelReady = true
        } catch {
            print("Error loading MLModel: \(error)")
            self.isModelReady = false
        }
    }
    
    func predict(features: [Float]) -> Double {
        guard let model = model else { return 0.0 }
        guard features.count == 16 else {
            print("Error: Expected 16 features, got \(features.count)")
            return 0.0
        }
        
        do {
            let multiArray = try MLMultiArray(shape: [16], dataType: .float32)
            for (index, value) in features.enumerated() {
                multiArray[index] = NSNumber(value: value)
            }
            
            let featureProvider = try MLDictionaryFeatureProvider(dictionary: ["features": multiArray])
            let prediction = try model.prediction(from: featureProvider)
            
            // Try getting probabilities from the dictionary output
            if let probabilities = prediction.featureValue(for: "probabilities")?.dictionaryValue as? [String: Double] {
                let prob = probabilities["sleep"] ?? 0.0
                self.sleepProbability = prob
                return prob
            }
            
            // Fallback: check classLabel directly
            if let label = prediction.featureValue(for: "classLabel")?.stringValue {
                let prob: Double = (label == "sleep") ? 0.8 : 0.2
                self.sleepProbability = prob
                return prob
            }
        } catch {
            print("Error during prediction: \(error)")
        }
        return 0.0
    }
    
    func reloadModel() {
        loadModel()
    }
}
