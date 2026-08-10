import Foundation
import CoreMotion

/// Monitors wrist movement via the accelerometer to detect periods of stillness
/// that may indicate the user is falling asleep.
///
/// Supports real Apple Watch hardware (CoreMotion) and Xcode Simulator mode.
@MainActor
final class MotionManager: ObservableObject {
    
    // MARK: - Published State
    
    /// Current movement intensity (0.0 = perfectly still, higher = more motion)
    @Published var movementScore: Double = 0.0
    
    /// Whether the user is currently considered "still" (below threshold)
    @Published var isStill: Bool = false
    
    /// How long the user has been continuously still (seconds)
    @Published var stillDuration: TimeInterval = 0
    
    /// Whether motion tracking is active
    @Published var isTracking: Bool = false
    
    /// Whether simulator fallback mode is active
    @Published var isSimulatorMode: Bool = false
    
    /// Manual override to force stillness in simulator for testing
    @Published var forceSimulatedStillness: Bool = false
    
    // MARK: - Private Properties
    
    private let motionManager = CMMotionManager()
    private var motionBuffer: [Double] = []
    private let bufferCapacity = 50 // 5 seconds at 10Hz
    private var stillnessStartTime: Date?
    private var settings: SessionSettings
    
    /// Previous acceleration values for delta calculation
    private var prevAcceleration: (x: Double, y: Double, z: Double)?
    
    /// Simulator timer for generating mock motion events
    private var simulatorTimer: Timer?
    
    // MARK: - Init
    
    init(settings: SessionSettings = .load()) {
        self.settings = settings
    }
    
    // MARK: - Public Methods
    
    /// Update the detection settings (e.g., when user changes sensitivity)
    func updateSettings(_ newSettings: SessionSettings) {
        self.settings = newSettings
    }
    
    /// Start accelerometer tracking
    func startTracking() {
        // Reset state
        motionBuffer.removeAll()
        prevAcceleration = nil
        stillnessStartTime = nil
        isStill = false
        stillDuration = 0
        movementScore = 0
        
        guard motionManager.isAccelerometerAvailable else {
            print("[MotionManager] Hardware accelerometer unavailable -> Entering Simulator Mode")
            startSimulatorTracking()
            return
        }
        
        isSimulatorMode = false
        
        // Configure update rate: 10Hz
        motionManager.accelerometerUpdateInterval = 0.1
        
        motionManager.startAccelerometerUpdates(to: OperationQueue()) { [weak self] data, error in
            guard let self = self, let acceleration = data?.acceleration else { return }
            
            Task { @MainActor in
                self.processAcceleration(x: acceleration.x, y: acceleration.y, z: acceleration.z)
            }
        }
        
        isTracking = true
    }
    
    /// Stop accelerometer tracking and reset state
    func stopTracking() {
        if isSimulatorMode {
            simulatorTimer?.invalidate()
            simulatorTimer = nil
        } else {
            motionManager.stopAccelerometerUpdates()
        }
        
        isTracking = false
        isStill = false
        stillDuration = 0
        movementScore = 0
        motionBuffer.removeAll()
        prevAcceleration = nil
        stillnessStartTime = nil
    }
    
    /// Toggle manual simulated stillness (helpful when testing in Xcode Simulator)
    func toggleSimulatedStillness() {
        forceSimulatedStillness.toggle()
        if !forceSimulatedStillness {
            // Reset stillness timer
            stillnessStartTime = nil
            isStill = false
            stillDuration = 0
        }
    }
    
    // MARK: - Simulator Fallback
    
    private func startSimulatorTracking() {
        isSimulatorMode = true
        isTracking = true
        
        simulatorTimer?.invalidate()
        // Simulate 10Hz accelerometer loop
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isTracking else { return }
                
                let simulatedX: Double
                let simulatedY: Double
                let simulatedZ: Double
                
                if self.forceSimulatedStillness {
                    // Micro-variations well below threshold
                    simulatedX = Double.random(in: 0.001...0.003)
                    simulatedY = Double.random(in: 0.001...0.003)
                    simulatedZ = Double.random(in: 0.001...0.003)
                } else {
                    // Active motion simulation
                    simulatedX = Double.random(in: 0.05...0.25)
                    simulatedY = Double.random(in: 0.05...0.25)
                    simulatedZ = Double.random(in: 0.05...0.25)
                }
                
                self.processAcceleration(x: simulatedX, y: simulatedY, z: simulatedZ)
            }
        }
    }
    
    // MARK: - Private Processing
    
    private func processAcceleration(x: Double, y: Double, z: Double) {
        // Calculate delta from previous reading
        let delta: Double
        if let prev = prevAcceleration {
            let dx = x - prev.x
            let dy = y - prev.y
            let dz = z - prev.z
            delta = sqrt(dx * dx + dy * dy + dz * dz)
        } else {
            delta = 0
        }
        prevAcceleration = (x, y, z)
        
        // Add to rolling buffer
        motionBuffer.append(delta)
        if motionBuffer.count > bufferCapacity {
            motionBuffer.removeFirst()
        }
        
        // Need at least 1 second of data (10 samples) before judging
        guard motionBuffer.count >= 10 else { return }
        
        // Calculate rolling average of movement deltas
        let averageDelta = motionBuffer.reduce(0, +) / Double(motionBuffer.count)
        movementScore = averageDelta
        
        // Determine stillness
        let wasStill = isStill
        let currentlyStill = forceSimulatedStillness || (averageDelta < settings.stillnessThreshold)
        
        if currentlyStill {
            if !wasStill {
                // Just became still — start the timer
                stillnessStartTime = Date()
            }
            
            if let startTime = stillnessStartTime {
                stillDuration = Date().timeIntervalSince(startTime)
            }
            
            isStill = true
        } else {
            // Movement detected — reset everything
            isStill = false
            stillDuration = 0
            stillnessStartTime = nil
        }
    }
}
