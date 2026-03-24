import Accelerate
import AVFoundation
import OSLog

/// Thread-safe container for filter state
private struct FilterState {
    var prevInput: Float = 0
    var prevOutput: Float = 0
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

    /// Creates a new audio preprocessor with the specified parameters.
    ///
    /// - Parameters:
    ///   - targetRMS: Target RMS level for normalization (default: 0.1 = -20dB)
    ///   - noiseGateThreshold: Minimum RMS to apply gain (default: 0.005)
    ///   - highPassCutoff: High-pass filter cutoff frequency in Hz (default: 150)
    ///   - maxGain: Maximum gain to apply (default: 10.0 = 20dB)
    public init(
        targetRMS: Float = 0.1,
        noiseGateThreshold: Float = 0.005,
        highPassCutoff: Float = 150.0,
        maxGain: Float = 10.0
    ) {
        self.targetRMS = targetRMS
        self.noiseGateThreshold = noiseGateThreshold
        self.highPassCutoff = highPassCutoff
        self.maxGain = maxGain
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

            // 2. Calculate RMS and apply gain normalization
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

            if rms > noiseGateThreshold {
                let gain = min(targetRMS / rms, maxGain)
                var scaledGain = gain
                vDSP_vsmul(channelData, 1, &scaledGain, channelData, 1, vDSP_Length(frameLength))
            }

            // 3. Soft limiting to prevent clipping
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
