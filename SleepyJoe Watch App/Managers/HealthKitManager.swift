import Foundation
import HealthKit

/// Manages real-time Heart Rate streaming via HKWorkoutSession and HKLiveWorkoutBuilder.
/// Builds a relative heart-rate baseline from initial samples and tracks fresh drops.
@MainActor
final class HealthKitManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    
    // MARK: - Published State
    
    @Published var currentHeartRate: Double = 0.0
    @Published var baselineHeartRate: Double = 0.0
    @Published var heartRateDropPercentage: Double = 0.0
    @Published var isHealthKitAuthorized: Bool = false
    @Published var isMonitoring: Bool = false
    private(set) var lastHeartRateSampleDate: Date?
    private var heartRateDropStartedAt: Date?
    var hasFreshHeartRate: Bool {
        guard isMonitoring else { return false }
        guard hrHistory.count >= 3, let lastHeartRateSampleDate else { return false }
        return Date().timeIntervalSince(lastHeartRateSampleDate) < 20
    }
    var hasRecentHeartRateDrop: Bool {
        guard hasFreshHeartRate, let heartRateDropStartedAt else { return false }
        return Date().timeIntervalSince(heartRateDropStartedAt) < 45
    }
    
    // MARK: - Private Properties
    
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    private var hrHistory: [Double] = []
    private let maxHistorySamples = 60
    
    // MARK: - Init
    
    override init() {
        super.init()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKitManager] HealthKit is not available on this device")
            return false
        }
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        do {
            // The live workout session is discarded after monitoring; Focus
            // neither reads existing workouts nor writes saved workout records.
            try await healthStore.requestAuthorization(toShare: [], read: [heartRateType])
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
        guard session == nil else { return }
        
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
                Task { @MainActor in
                    guard let self = self, self.session === newSession else { return }
                    guard success else {
                        print("[HealthKitManager] Failed to begin collection: \(error?.localizedDescription ?? "unknown")")
                        self.stopMonitoring()
                        return
                    }
                    self.isMonitoring = true
                    print("[HealthKitManager] Started continuous Heart Rate monitoring & background session")
                }
            }
        } catch {
            print("[HealthKitManager] Failed to start workout session: \(error.localizedDescription)")
        }
    }
    
    func stopMonitoring() {
        let oldSession = session
        let oldBuilder = builder
        session = nil
        builder = nil
        isMonitoring = false
        hrHistory.removeAll()
        lastHeartRateSampleDate = nil
        currentHeartRate = 0
        baselineHeartRate = 0
        heartRateDropPercentage = 0
        heartRateDropStartedAt = nil
        let endDate = Date()
        oldSession?.stopActivity(with: endDate)
        if let oldBuilder {
            oldBuilder.endCollection(withEnd: endDate) { _, _ in
                // Focus monitoring is not an exercise workout.
                oldBuilder.discardWorkout()
                oldSession?.end()
            }
        } else {
            oldSession?.end()
        }
    }
    
    // MARK: - Processing
    
    private func processNewHeartRate(_ hr: Double) {
        guard hr > 30 && hr < 220 else { return }
        guard session != nil else { return }
        
        currentHeartRate = hr
        lastHeartRateSampleDate = Date()
        hrHistory.append(hr)
        if hrHistory.count > maxHistorySamples { hrHistory.removeFirst() }
        
        if hrHistory.count <= 3 {
            // A single noisy first reading must not establish the resting baseline.
            baselineHeartRate = hrHistory.reduce(0, +) / Double(hrHistory.count)
            heartRateDropPercentage = 0
            heartRateDropStartedAt = nil
            return
        } else {
            // Track waking drift slowly enough that a genuine short drop remains visible.
            baselineHeartRate = (baselineHeartRate * 0.995) + (hr * 0.005)
        }
        
        if baselineHeartRate > 0 {
            let previousDrop = heartRateDropPercentage
            let drop = max(0, (baselineHeartRate - currentHeartRate) / baselineHeartRate)
            heartRateDropPercentage = drop
            if drop >= 0.05 && previousDrop < 0.05 {
                heartRateDropStartedAt = Date()
            } else if drop < 0.05 {
                heartRateDropStartedAt = nil
            }
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
                guard self.builder === workoutBuilder else { return }
                self.processNewHeartRate(value)
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    
    // MARK: - HKWorkoutSessionDelegate
    
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            Task { @MainActor in
                guard self.session === workoutSession else { return }
                self.builder?.discardWorkout()
                self.builder = nil
                self.session = nil
                self.isMonitoring = false
                self.heartRateDropPercentage = 0
                self.heartRateDropStartedAt = nil
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKitManager] Workout session error: \(error.localizedDescription)")
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.builder?.discardWorkout()
            self.builder = nil
            self.session = nil
            self.isMonitoring = false
            self.heartRateDropPercentage = 0
            self.heartRateDropStartedAt = nil
        }
    }
}
