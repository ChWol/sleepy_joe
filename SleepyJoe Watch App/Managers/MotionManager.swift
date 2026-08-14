import Foundation
import CoreMotion

/// Monitors wrist movement via device motion & accelerometer to detect
/// micro-jitter stillness and posture pitch drop (arm sagging or resting).
@MainActor
final class MotionManager: ObservableObject {
    
    // MARK: - Published State
    
    /// Current movement intensity (0.0 = perfectly still, higher = more motion)
    @Published var movementScore: Double = 0.0
    
    /// Current wrist pitch angle in degrees (-90° to +90°)
    @Published var pitchDegrees: Double = 0.0
    
    /// Whether a posture drop or resting tilt (arm sagging or angled down) was detected
    @Published var isPitchDropDetected: Bool = false
    
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
    
    /// Recent pitch history for telemetry windowing
    var pitchDegreesHistory: [Double] { pitchBuffer }
    
    /// Recent motion delta history for telemetry windowing
    var motionDeltaHistory: [Double] { motionBuffer }
    
    /// Raw acceleration X values for feature extraction
    var rawAccelXHistory: [Float] { rawAccelX }
    var rawAccelYHistory: [Float] { rawAccelY }
    var rawAccelZHistory: [Float] { rawAccelZ }
    
    // MARK: - Private Properties
    
    private let motionManager = CMMotionManager()
    private var motionBuffer: [Double] = []
    private var pitchBuffer: [Double] = []
    private var rawAccelX: [Float] = []
    private var rawAccelY: [Float] = []
    private var rawAccelZ: [Float] = []
    private let bufferCapacity = 50 // 5 seconds at 10Hz
    private var stillnessStartTime: Date?
    private var settings: SessionSettings
    
    private var prevAcceleration: (x: Double, y: Double, z: Double)?
    private var simulatorTimer: Timer?
    
    // MARK: - Init
    
    init(settings: SessionSettings = .load()) {
        self.settings = settings
    }
    
    // MARK: - Public Methods
    
    func updateSettings(_ newSettings: SessionSettings) {
        self.settings = newSettings
    }
    
    func startTracking() {
        motionBuffer.removeAll()
        pitchBuffer.removeAll()
        rawAccelX.removeAll()
        rawAccelY.removeAll()
        rawAccelZ.removeAll()
        prevAcceleration = nil
        stillnessStartTime = nil
        isStill = false
        isPitchDropDetected = false
        stillDuration = 0
        movementScore = 0
        pitchDegrees = 0
        
        guard motionManager.isDeviceMotionAvailable else {
            print("[MotionManager] Hardware DeviceMotion unavailable -> Entering Simulator Mode")
            startSimulatorTracking()
            return
        }
        
        isSimulatorMode = false
        motionManager.deviceMotionUpdateInterval = 0.1 // 10Hz
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            let pitch = motion.attitude.pitch * (180.0 / .pi) // Convert radians to degrees
            let acc = motion.userAcceleration
            
            self.processMotion(x: acc.x, y: acc.y, z: acc.z, pitch: pitch)
        }
        
        isTracking = true
    }
    
    func stopTracking() {
        if isSimulatorMode {
            simulatorTimer?.invalidate()
            simulatorTimer = nil
        } else {
            motionManager.stopDeviceMotionUpdates()
        }
        
        isTracking = false
        isStill = false
        isPitchDropDetected = false
        stillDuration = 0
        movementScore = 0
        pitchDegrees = 0
        motionBuffer.removeAll()
        pitchBuffer.removeAll()
        rawAccelX.removeAll()
        rawAccelY.removeAll()
        rawAccelZ.removeAll()
        prevAcceleration = nil
        stillnessStartTime = nil
    }
    
    func toggleSimulatedStillness() {
        forceSimulatedStillness.toggle()
        if !forceSimulatedStillness {
            stillnessStartTime = nil
            isStill = false
            isPitchDropDetected = false
            stillDuration = 0
        }
    }
    
    // MARK: - Simulator Fallback
    
    private func startSimulatorTracking() {
        isSimulatorMode = true
        isTracking = true
        
        simulatorTimer?.invalidate()
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isTracking else { return }
                
                let simulatedX: Double
                let simulatedY: Double
                let simulatedZ: Double
                let simulatedPitch: Double
                
                if self.forceSimulatedStillness {
                    simulatedX = Double.random(in: 0.001...0.002)
                    simulatedY = Double.random(in: 0.001...0.002)
                    simulatedZ = Double.random(in: 0.001...0.002)
                    simulatedPitch = -35.0
                } else {
                    simulatedX = Double.random(in: 0.05...0.25)
                    simulatedY = Double.random(in: 0.05...0.25)
                    simulatedZ = Double.random(in: 0.05...0.25)
                    simulatedPitch = 0.0
                }
                
                self.processMotion(x: simulatedX, y: simulatedY, z: simulatedZ, pitch: simulatedPitch)
            }
        }
    }
    
    // MARK: - Private Processing
    
    private func processMotion(x: Double, y: Double, z: Double, pitch: Double) {
        pitchDegrees = pitch
        
        pitchBuffer.append(pitch)
        if pitchBuffer.count > bufferCapacity {
            pitchBuffer.removeFirst()
        }
        
        rawAccelX.append(Float(x))
        rawAccelY.append(Float(y))
        rawAccelZ.append(Float(z))
        
        if rawAccelX.count > bufferCapacity {
            rawAccelX.removeFirst()
            rawAccelY.removeFirst()
            rawAccelZ.removeFirst()
        }
        
        // Pitch drop / resting tilt detection:
        // Requires dynamic pitch sagging (>12 degrees drop during window) OR arm hanging vertically down (<-60 deg)
        // Does NOT flag normal flat/downward desk resting posture (-15 to -35 deg) as falling asleep!
        var relativeDrop = false
        if pitchBuffer.count >= 20 {
            let initialPitch = pitchBuffer.prefix(10).reduce(0, +) / 10.0
            let currentPitchAverage = pitchBuffer.suffix(10).reduce(0, +) / 10.0
            relativeDrop = (initialPitch - currentPitchAverage) > 12.0
        }
        
        let hangingArm = pitch < -60.0
        isPitchDropDetected = forceSimulatedStillness || relativeDrop || hangingArm
        
        // Acceleration Delta
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
        
        motionBuffer.append(delta)
        if motionBuffer.count > bufferCapacity {
            motionBuffer.removeFirst()
        }
        
        guard motionBuffer.count >= 10 else { return }
        
        let averageDelta = motionBuffer.reduce(0, +) / Double(motionBuffer.count)
        movementScore = averageDelta
        
        let wasStill = isStill
        let currentlyStill = forceSimulatedStillness || (averageDelta < settings.stillnessThreshold)
        
        if currentlyStill {
            if !wasStill {
                stillnessStartTime = Date()
            }
            if let startTime = stillnessStartTime {
                stillDuration = Date().timeIntervalSince(startTime)
            }
            isStill = true
        } else {
            isStill = false
            stillDuration = 0
            stillnessStartTime = nil
        }
    }
}
