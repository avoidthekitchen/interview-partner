import Accelerate
import AVFoundation
import OSLog

/// Thread-safe container for filter state
private struct FilterState {
    var prevInput: Float = 0
    var prevOutput: Float = 0
}

/// Spectral noise suppressor using power-spectrum subtraction.
///
/// Maintains a running per-bin noise floor estimate and applies a gain mask that
/// suppresses frequency bins below the estimated noise floor.  The estimate only
/// updates during non-speech frames (RMS below the noise-gate threshold), so
/// speech does not inflate the noise model.
///
/// Algorithm: H(k) = max(1 − α·N(k)/|X(k)|, β)  where α is the over-subtraction
/// factor and β is the spectral floor that prevents complete bin erasure.
private final class SpectralDenoiser {
    // Noise floor update rate (0 = freeze, 1 = instant). Applied only during silence.
    private let noiseUpdateRate: Float
    // Over-subtraction factor — how aggressively to remove noise (1.0–3.0 typical).
    private let overSubtractionFactor: Float
    // Minimum gain per bin. Prevents "musical noise" (spectral holes) sounding worse than the original.
    private let spectralFloor: Float

    // Cached state, guarded by `lock`
    private var noiseEstimate: [Float] = []
    private var fftSetup: OpaquePointer?
    private var currentLog2N: vDSP_Length = 0
    // Pre-allocated work buffers, resized when FFT size changes
    private var workBuf: [Float] = []
    private var realBuf: [Float] = []
    private var imagBuf: [Float] = []
    private var magBuf: [Float] = []

    private let lock = NSLock()

    init(
        noiseUpdateRate: Float = 0.10,
        overSubtractionFactor: Float = 1.5,
        spectralFloor: Float = 0.05
    ) {
        self.noiseUpdateRate = noiseUpdateRate
        self.overSubtractionFactor = overSubtractionFactor
        self.spectralFloor = spectralFloor
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    func process(_ data: UnsafeMutablePointer<Float>, frameCount: Int, isSpeech: Bool) {
        lock.withLock { _process(data, frameCount: frameCount, isSpeech: isSpeech) }
    }

    // swiftlint:disable:next function_body_length
    private func _process(_ data: UnsafeMutablePointer<Float>, frameCount: Int, isSpeech: Bool) {
        guard frameCount > 0 else { return }

        // Round frameCount up to the nearest power of 2 for the FFT
        var n = 1
        while n < frameCount { n <<= 1 }
        let log2n = vDSP_Length(log2(Double(n)))

        // Rebuild setup and resize buffers when the FFT size changes
        if log2n != currentLog2N {
            if let old = fftSetup { vDSP_destroy_fftsetup(old) }
            guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
            fftSetup = setup
            currentLog2N = log2n

            workBuf = [Float](repeating: 0, count: n)
            realBuf = [Float](repeating: 0, count: n / 2)
            imagBuf = [Float](repeating: 0, count: n / 2)
            magBuf  = [Float](repeating: 0, count: n / 2 + 1)
            // Start noise estimate near silence so it adapts quickly on the first few frames
            noiseEstimate = [Float](repeating: 1e-12, count: n / 2 + 1)
        }
        guard let setup = fftSetup else { return }

        let halfN = n / 2

        // --- Copy input into zero-padded work buffer ---
        workBuf.withUnsafeMutableBufferPointer { wBuf in
            let wp = wBuf.baseAddress!
            for i in 0..<frameCount { wp[i] = data[i] }
            for i in frameCount..<n    { wp[i] = 0 }
        }

        realBuf.withUnsafeMutableBufferPointer { rBuf in
            imagBuf.withUnsafeMutableBufferPointer { iBuf in
                let rp = rBuf.baseAddress!
                let ip = iBuf.baseAddress!

                // --- Pack real array as split complex (even→realp, odd→imagp) ---
                workBuf.withUnsafeBytes { wBytes in
                    let cp = wBytes.bindMemory(to: DSPComplex.self).baseAddress!
                    var split = DSPSplitComplex(realp: rp, imagp: ip)
                    vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(halfN))
                }

                var split = DSPSplitComplex(realp: rp, imagp: ip)

                // --- Forward FFT ---
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // --- Magnitude per bin (DC at rp[0], Nyquist at ip[0]) ---
                magBuf.withUnsafeMutableBufferPointer { mBuf in
                    let mp = mBuf.baseAddress!
                    mp[0]     = abs(rp[0])   // DC
                    mp[halfN] = abs(ip[0])   // Nyquist
                    for k in 1..<halfN {
                        mp[k] = sqrt(rp[k] * rp[k] + ip[k] * ip[k])
                    }

                    // --- Update noise estimate during silence ---
                    if !isSpeech {
                        let rate = noiseUpdateRate
                        for i in 0...(halfN) {
                            noiseEstimate[i] = (1.0 - rate) * noiseEstimate[i] + rate * mp[i]
                        }
                    }

                    // --- Apply spectral subtraction gain ---
                    let alpha = overSubtractionFactor
                    let beta  = spectralFloor
                    for k in 0...(halfN) {
                        let m = mp[k]
                        let gain: Float = m > 1e-10
                            ? max(1.0 - alpha * noiseEstimate[k] / m, beta)
                            : beta
                        if k == 0       { rp[0] *= gain }
                        else if k == halfN { ip[0] *= gain }
                        else           { rp[k] *= gain; ip[k] *= gain }
                    }
                }

                // --- Inverse FFT ---
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))

                // --- Unpack split complex back to interleaved real ---
                workBuf.withUnsafeMutableBytes { wBytes in
                    let cp = wBytes.bindMemory(to: DSPComplex.self).baseAddress!
                    vDSP_ztoc(&split, 1, cp, 2, vDSP_Length(halfN))
                }
            }
        }

        // --- Scale and copy back (vDSP forward×2, inverse×N → net 2N) ---
        let scale = Float(1.0 / Double(2 * n))
        workBuf.withUnsafeBufferPointer { wBuf in
            let wp = wBuf.baseAddress!
            for i in 0..<frameCount { data[i] = wp[i] * scale }
        }
    }
}

/// Preprocesses audio buffers to improve transcription quality in real-world conditions.
/// Applies RMS normalization, high-pass filtering, and soft limiting.
@preconcurrency public final class AudioPreprocessor: @unchecked Sendable {
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "AudioPreprocessor"
    )

    private let targetRMS: Float
    private let noiseGateThreshold: Float
    private let highPassCutoff: Float
    private let maxGain: Float
    private let denoiser: SpectralDenoiser?

    /// Creates a new audio preprocessor with the specified parameters.
    ///
    /// - Parameters:
    ///   - targetRMS: Target RMS level for normalization (default: 0.1 = -20dB)
    ///   - noiseGateThreshold: Minimum RMS to apply gain (default: 0.005)
    ///   - highPassCutoff: High-pass filter cutoff frequency in Hz (default: 150)
    ///   - maxGain: Maximum gain to apply (default: 10.0 = 20dB)
    ///   - enableSpectralDenoising: Apply FFT-based spectral subtraction (default: false —
    ///     benchmarks show the HPF+RMS pipeline already handles common noise sources, and
    ///     spectral subtraction introduces artefacts that regress WER on both clean and noisy audio)
    public init(
        targetRMS: Float = 0.1,
        noiseGateThreshold: Float = 0.005,
        highPassCutoff: Float = 150.0,
        maxGain: Float = 10.0,
        enableSpectralDenoising: Bool = false
    ) {
        self.targetRMS = targetRMS
        self.noiseGateThreshold = noiseGateThreshold
        self.highPassCutoff = highPassCutoff
        self.maxGain = maxGain
        self.denoiser = enableSpectralDenoising ? SpectralDenoiser() : nil
    }

    /// Processes an audio buffer in-place, applying normalization and filtering.
    ///
    /// - Parameter buffer: The audio buffer to process (modified in-place)
    public func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)

        // Use local state for filter (stateless across calls for thread safety)
        var filterState = FilterState()

        // Process each channel
        for channel in 0..<Int(buffer.format.channelCount) {
            let channelData = data[channel]

            // 1. High-pass filter to remove low-frequency rumble
            applyHighPassFilter(channelData, frameCount: frameLength, sampleRate: sampleRate, state: &filterState)

            // 2. Calculate RMS (needed for noise gate decision in spectral denoiser)
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

            // 3. Spectral noise suppression (updates noise model only during silence)
            denoiser?.process(channelData, frameCount: frameLength, isSpeech: rms > noiseGateThreshold * 2)

            // 4. RMS normalization
            if rms > noiseGateThreshold {
                let gain = min(targetRMS / rms, maxGain)
                var scaledGain = gain
                vDSP_vsmul(channelData, 1, &scaledGain, channelData, 1, vDSP_Length(frameLength))
            }

            // 5. Soft limiting to prevent clipping
            applySoftLimit(channelData, frameCount: frameLength)
        }
    }

    /// Processes a copy of the audio buffer, returning a new buffer.
    ///
    /// - Parameter buffer: The source audio buffer
    /// - Returns: A new buffer containing the processed audio
    public func processCopy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Create a copy manually since deepCopy is fileprivate in another file
        guard let copiedBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else {
            return buffer
        }
        copiedBuffer.frameLength = buffer.frameLength

        // Copy audio data
        if let src = buffer.floatChannelData,
           let dst = copiedBuffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                dst[channel].update(from: src[channel], count: Int(buffer.frameLength))
            }
        }

        process(copiedBuffer)
        return copiedBuffer
    }

    // MARK: - Private

    /// Applies a single-pole high-pass IIR filter.
    /// Formula: y[n] = x[n] - x[n-1] + α*y[n-1]
    /// where α = 1 - 2π*fc/fs
    private func applyHighPassFilter(_ data: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Float, state: inout FilterState) {
        let alpha = 1.0 - (2.0 * .pi * highPassCutoff / sampleRate)

        for i in 0..<frameCount {
            let input = data[i]
            let output = input - state.prevInput + alpha * state.prevOutput
            data[i] = output
            state.prevInput = input
            state.prevOutput = output
        }
    }

    /// Applies tanh-based soft limiting to prevent clipping.
    private func applySoftLimit(_ data: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let sample = data[i]
            // Tanh-based soft limiter with 1.5x gain
            data[i] = tanh(sample * 1.5) / 1.5
        }
    }
}
