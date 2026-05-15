import Foundation

// Phase 2 — RMS → normalisierte Balkenhöhen für die Overlay-Visualisierung
// Portiert von ui/overlay_levels.py (VisualLevelMapper)
final class OverlayLevelMapper {
    private var noiseFloor: Float = 0.0015
    private var speechPeak: Float = 0.0200
    private var smoothed: Float = 0.0

    static let barCount = 9

    // MARK: - Public

    /// Gibt barCount normalisierte Höhen (0…1) für die aktuelle RMS zurück.
    func barHeights(rms: Float, phase: Double) -> [Double] {
        let level = Double(map(rms: rms))
        return (0..<Self.barCount).map { i in
            let phaseOffset = Double(i) * (.pi * 2.0 / Double(Self.barCount))
            let wave = sin(phase + phaseOffset) * 0.18 + 0.82
            return min(1.0, max(0.0, level * wave))
        }
    }

    func reset() {
        noiseFloor = 0.0015
        speechPeak = 0.0200
        smoothed = 0.0
    }

    // MARK: - Internal

    private func map(rms: Float) -> Float {
        let rms = max(0.0, rms)

        // Noise-floor adaptiv tracken
        if rms < noiseFloor * 1.8 {
            noiseFloor = 0.98 * noiseFloor + 0.02 * rms
        } else {
            noiseFloor = 0.995 * noiseFloor + 0.005 * min(rms, noiseFloor * 2.5)
        }

        let signal = max(0.0, rms - noiseFloor * 1.35)
        guard signal > 0.0008 else {
            speechPeak *= 0.996
            smoothed = smoothed * 0.7
            return smoothed
        }

        if signal > speechPeak {
            speechPeak = 0.70 * speechPeak + 0.30 * signal
        } else {
            speechPeak = max(0.006, speechPeak * 0.997)
        }

        let normalized = min(1.0, signal / max(speechPeak, 0.006))
        let level = max(0.16, pow(normalized, 0.55))

        // Exponentielles Smoothing (α = 0.3)
        smoothed = smoothed * 0.7 + level * 0.3
        return smoothed
    }
}
