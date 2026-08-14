import Foundation
import HealthKit

/// Manages real-time Heart Rate streaming via HKWorkoutSession and HKLiveWorkoutBuilder.
/// Instantly seeds resting baseline on first sample and tracks relative HR drops without delay.
@MainActor
final class HealthKitManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    
    // MARK: - Published State
    
    @Published var currentHeartRate: Double = 0.0
    @Published var baselineHeartRate: Double = 0.0
    @Published var heartRateDropPercentage: Double = 0.0
    @Published var isHealthKitAuthorized: Bool = false
    @Published var isMonitoring: Bool = false
    
    // MARK: - Private Properties
    
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    private var hrHistory: [Double] = []
    private let maxHistorySamples = 60
    
    // MARK: - Init
    
    override init() {
        super.init()
        Task {
            let _ = await requestAuthorization()
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKitManager] HealthKit is not available on this device")
            return false
        }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let workoutType = HKObjectType.workoutType()
        
        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType, workoutType])
            isHealthKitAuthorized = true
            return true
        } catch {
            print("[HealthKitManager] Authorization failed: \(error.localizedDescription)")
            isHealthKitAuthorized = false
            return false
        }
    }
    
    // MARK: - Live Workout Session Control
    
    func startMonitoring() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        
        do {
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            
            self.session = newSession
            self.builder = newBuilder
            
            newSession.delegate = self
            newBuilder.delegate = self
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            // Prepare hardware sensors for instant background execution
            newSession.prepare()
            newSession.startActivity(with: Date())
            
            newBuilder.beginCollection(withStart: Date()) { [weak self] success, error in
                guard let self = self, success else {
                    print("[HealthKitManager] Failed to begin collection: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                Task { @MainActor in
                    self.isMonitoring = true
                    print("[HealthKitManager] Started continuous Heart Rate monitoring & background session")
                }
            }
        } catch {
            print("[HealthKitManager] Failed to start workout session: \(error.localizedDescription)")
        }
    }
    
    func stopMonitoring() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            Task { @MainActor in
                self?.isMonitoring = false
                self?.hrHistory.removeAll()
                self?.currentHeartRate = 0.0
                self?.baselineHeartRate = 0.0
                self?.heartRateDropPercentage = 0.0
                print("[HealthKitManager] Stopped Heart Rate monitoring")
            }
        }
    }
    
    // MARK: - Processing
    
    private func processNewHeartRate(_ hr: Double) {
        guard hr > 30 && hr < 220 else { return }
        
        currentHeartRate = hr
        
        if baselineHeartRate == 0.0 {
            // Seed baseline instantly from first valid sample
            baselineHeartRate = hr
        } else {
            // Slowly adapt baseline using Exponential Moving Average
            baselineHeartRate = (baselineHeartRate * 0.9) + (hr * 0.1)
        }
        
        hrHistory.append(hr)
        if hrHistory.count > maxHistorySamples {
            hrHistory.removeFirst()
        }
        
        if baselineHeartRate > 0 {
            let drop = max(0, (baselineHeartRate - currentHeartRate) / baselineHeartRate)
            heartRateDropPercentage = drop
        } else {
            heartRateDropPercentage = 0.0
        }
    }
    
    // MARK: - HKLiveWorkoutBuilderDelegate
    
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType) else { return }
        
        if let statistics = workoutBuilder.statistics(for: heartRateType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? 0.0
            
            Task { @MainActor in
                self.processNewHeartRate(value)
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    
    // MARK: - HKWorkoutSessionDelegate
    
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKitManager] Workout session error: \(error.localizedDescription)")
    }
}
