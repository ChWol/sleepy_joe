import Foundation
import Accelerate

/// Extracts physiological features from 5-second sensor windows
struct FeatureExtractor {
    
    /// Computes 16 physiological features from raw sensor arrays using vDSP
    /// - Parameters:
    ///   - x: Raw acceleration X (e.g., 50 samples)
    ///   - y: Raw acceleration Y
    ///   - z: Raw acceleration Z
    ///   - pitch: Wrist pitch in degrees
    /// - Returns: An array of 16 extracted features
    static func extractFeatures(x: [Float], y: [Float], z: [Float], pitch: [Float]) -> [Float] {
        guard !x.isEmpty, x.count == y.count, x.count == z.count, x.count == pitch.count else {
            return Array(repeating: 0.0, count: 16)
        }
        
        let n = vDSP_Length(x.count)
        let nf = Float(x.count)
        
        // 0-2 & 11: Means
        var meanX: Float = 0
        var meanY: Float = 0
        var meanZ: Float = 0
        var meanPitch: Float = 0
        
        vDSP_meanv(x, 1, &meanX, n)
        vDSP_meanv(y, 1, &meanY, n)
        vDSP_meanv(z, 1, &meanZ, n)
        vDSP_meanv(pitch, 1, &meanPitch, n)
        
        // Helper to compute variance using vDSP
        func computeVariance(_ arr: [Float], mean: Float) -> Float {
            var meanNeg = -mean
            var centered = [Float](repeating: 0, count: Int(n))
            vDSP_vsadd(arr, 1, &meanNeg, &centered, 1, n)
            var sumSq: Float = 0
            vDSP_svesq(centered, 1, &sumSq, n)
            return sumSq / nf
        }
        
        // 3-5 & 13: Variances
        let varX = computeVariance(x, mean: meanX)
        let varY = computeVariance(y, mean: meanY)
        let varZ = computeVariance(z, mean: meanZ)
        let varPitch = computeVariance(pitch, mean: meanPitch)
        
        // 6: Total Jitter Variance = (varX² + varY² + varZ²) / 3
        let totalJitterVar = (varX * varX + varY * varY + varZ * varZ) / 3.0
        
        // 7: Signal Magnitude Area (SMA) = sum(|x|+|y|+|z|) / N
        var absX = [Float](repeating: 0, count: Int(n))
        var absY = [Float](repeating: 0, count: Int(n))
        var absZ = [Float](repeating: 0, count: Int(n))
        
        vDSP_vabs(x, 1, &absX, 1, n)
        vDSP_vabs(y, 1, &absY, 1, n)
        vDSP_vabs(z, 1, &absZ, 1, n)
        
        var sumAbsX: Float = 0, sumAbsY: Float = 0, sumAbsZ: Float = 0
        vDSP_sve(absX, 1, &sumAbsX, n)
        vDSP_sve(absY, 1, &sumAbsY, n)
        vDSP_sve(absZ, 1, &sumAbsZ, n)
        let sma = (sumAbsX + sumAbsY + sumAbsZ) / nf
        
        // 8-10: Peak-to-Peak
        var minX: Float = 0, maxX: Float = 0
        var minY: Float = 0, maxY: Float = 0
        var minZ: Float = 0, maxZ: Float = 0
        
        vDSP_minv(x, 1, &minX, n)
        vDSP_maxv(x, 1, &maxX, n)
        vDSP_minv(y, 1, &minY, n)
        vDSP_maxv(y, 1, &maxY, n)
        vDSP_minv(z, 1, &minZ, n)
        vDSP_maxv(z, 1, &maxZ, n)
        
        let p2pX = maxX - minX
        let p2pY = maxY - minY
        let p2pZ = maxZ - minZ
        
        // 12: Pitch Delta
        let pitchDelta = (pitch.last ?? 0) - (pitch.first ?? 0)
        
        // 14: Zero Crossing Rate / N (Mean-centered)
        func zcrCentered(_ arr: [Float], mean: Float) -> Float {
            var crossings: Float = 0
            for i in 1..<arr.count {
                let a = arr[i-1] - mean
                let b = arr[i] - mean
                if (a > 0 && b < 0) || (a < 0 && b > 0) {
                    crossings += 1
                }
            }
            return crossings
        }
        
        let zcrX = zcrCentered(x, mean: meanX)
        let zcrY = zcrCentered(y, mean: meanY)
        let zcrZ = zcrCentered(z, mean: meanZ)
        let zcrNorm = (zcrX + zcrY + zcrZ) / (3.0 * nf)
        
        // 15: Peak Energy = max(x)² + max(y)² + max(z)²
        var maxAbsX: Float = 0, maxAbsY: Float = 0, maxAbsZ: Float = 0
        vDSP_maxv(absX, 1, &maxAbsX, n)
        vDSP_maxv(absY, 1, &maxAbsY, n)
        vDSP_maxv(absZ, 1, &maxAbsZ, n)
        let peakEnergy = (maxAbsX * maxAbsX) + (maxAbsY * maxAbsY) + (maxAbsZ * maxAbsZ)
        
        return [
            meanX, meanY, meanZ,                // 0-2
            varX, varY, varZ,                   // 3-5
            totalJitterVar,                     // 6
            sma,                                // 7
            p2pX, p2pY, p2pZ,                   // 8-10
            meanPitch,                          // 11
            pitchDelta,                         // 12
            varPitch,                           // 13
            zcrNorm,                            // 14
            peakEnergy                          // 15
        ]
    }
    
    /// Convenience method that takes [Double] arrays and converts them for processing
    static func extractFeatures(x: [Double], y: [Double], z: [Double], pitch: [Double]) -> [Float] {
        return extractFeatures(
            x: x.map { Float($0) },
            y: y.map { Float($0) },
            z: z.map { Float($0) },
            pitch: pitch.map { Float($0) }
        )
    }
}
