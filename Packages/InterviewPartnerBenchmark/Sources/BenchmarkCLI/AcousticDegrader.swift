import Accelerate
import AVFoundation
import InterviewPartnerServices

/// Simulates acoustic degradation to benchmark transcription robustness under real-world conditions.
///
/// Applies white noise and a low-pass rolloff to simulate the speaker→air→microphone path:
/// - `light`:    ~20dB SNR, gentle 8kHz rolloff
/// - `moderate`: ~10dB SNR, harder 4kHz rolloff
/// - `heavy`:    ~5dB SNR,  aggressive 2kHz rolloff + random gain variation
struct AcousticDegrader: Sendable {

    enum Level: String, Sendable, CaseIterable {
        case light
        case moderate
        case heavy

        var noiseAmplitude: Float {
            switch self {
            case .light:    return 0.010   // ~-40dBFS noise floor, ~20dB SNR on speech
            case .moderate: return 0.032   // ~-30dBFS, ~10dB SNR
            case .heavy:    return 0.056   // ~-25dBFS, ~5dB SNR
            }
        }

        /// One-pole low-pass IIR coefficient. Higher = more rolloff.
        var lpfAlpha: Float {
            switch self {
            case .light:    return 0.12   // ~8kHz rolloff at 16kHz sample rate
            case .moderate: return 0.30   // ~4kHz rolloff
            case .heavy:    return 0.55   // ~2kHz rolloff
            }
        }

        var gainVariation: Bool { self == .heavy }
    }

    let level: Level

    /// Degrades `buffer` in-place and returns it.
    func degrade(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let data = buffer.floatChannelData else { return buffer }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return buffer }

        let samples = data[0]
        let alpha = level.lpfAlpha
        let noiseAmp = level.noiseAmplitude

        // 1. Low-pass filter (one-pole IIR): y[n] = (1-α)*x[n] + α*y[n-1]
        var prev: Float = 0
        for i in 0..<n {
            let filtered = (1.0 - alpha) * samples[i] + alpha * prev
            samples[i] = filtered
            prev = filtered
        }

        // 2. Add white noise using a fast LCG PRNG
        var seed: UInt32 = arc4random()
        var noiseBuffer = [Float](repeating: 0, count: n)
        for i in 0..<n {
            seed = seed &* 1664525 &+ 1013904223
            let f = Float(bitPattern: (seed >> 9) | 0x3F800000) - 1.5
            noiseBuffer[i] = f * noiseAmp
        }
        vDSP_vadd(samples, 1, noiseBuffer, 1, samples, 1, vDSP_Length(n))

        // 3. Heavy: random per-buffer gain variation (simulates distance/movement)
        if level.gainVariation {
            var gain: Float = 0.7 + Float(arc4random_uniform(60)) / 100.0
            vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(n))
        }

        return buffer
    }
}

/// Wraps `FileAudioReplayer`, applying `AcousticDegrader` to every delivered buffer.
final class DegradedAudioProvider: AudioSampleProvider, @unchecked Sendable {
    private let replayer: FileAudioReplayer
    private let degrader: AcousticDegrader

    var audioFormat: AVAudioFormat { replayer.audioFormat }

    init(replayer: FileAudioReplayer, degrader: AcousticDegrader) {
        self.replayer = replayer
        self.degrader = degrader
    }

    func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try replayer.start { [degrader] buffer in
            handler(degrader.degrade(buffer))
        }
    }

    func stop() {
        replayer.stop()
    }
}
