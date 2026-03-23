@preconcurrency import AVFoundation
import OSLog

/// An ``AudioSampleProvider`` that reads audio samples from a file and
/// delivers them at real-time rate, simulating a live microphone feed.
///
/// Useful for replay-based testing and offline transcription evaluation.
public final class FileAudioReplayer: @unchecked Sendable {
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "FileAudioReplayer"
    )

    private let fileURL: URL
    private let bufferFrameCount: AVAudioFrameCount

    /// The audio format of delivered buffers. When format conversion is
    /// needed this reflects the *output* format (matching typical input-node
    /// output format: 16-kHz Float32 mono). When the source file already
    /// matches, no conversion takes place.
    private var outputFormat: AVAudioFormat

    /// Background task that drives the real-time paced read loop.
    private var deliveryTask: Task<Void, Never>?

    /// Creates a replayer for the given audio file.
    ///
    /// - Parameters:
    ///   - fileURL: Path to the audio file (`.mov`, `.m4a`, `.wav`, etc.).
    ///   - bufferFrameCount: Number of frames per delivered buffer.
    ///     Defaults to 2048, matching ``MicrophoneAudioProvider``'s tap size.
    ///   - outputSampleRate: The sample rate expected by downstream consumers.
    ///     Pass `nil` to deliver buffers in the file's native format.
    public init(
        fileURL: URL,
        bufferFrameCount: AVAudioFrameCount = 2048,
        outputSampleRate: Double? = nil
    ) {
        self.fileURL = fileURL
        self.bufferFrameCount = bufferFrameCount

        // Provide a sensible default that will be overwritten in `start`.
        // We pick standard Float32 mono at 48 kHz as a placeholder since
        // the real format isn't known until the file is opened.
        if let sampleRate = outputSampleRate {
            self.outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )!
        } else {
            self.outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: 48_000,
                channels: 1
            )!
        }
    }
}

// MARK: - AudioSampleProvider

extension FileAudioReplayer: AudioSampleProvider {

    public var audioFormat: AVAudioFormat {
        outputFormat
    }

    public func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        // Open the file up-front so we can fail synchronously if the path
        // is invalid, then hand the open file to the background task.
        let audioFile = try AVAudioFile(forReading: fileURL)
        let sourceFormat = audioFile.processingFormat

        let needsConversion = sourceFormat.sampleRate != outputFormat.sampleRate
            || sourceFormat.channelCount != outputFormat.channelCount

        // If no custom output sample rate was requested, just use the file's
        // native format (avoids an unnecessary conversion step).
        if !needsConversion {
            outputFormat = sourceFormat
        }

        let converter: AVAudioConverter?
        if needsConversion {
            guard let c = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                throw FileAudioReplayerError.formatConversionUnavailable(
                    source: sourceFormat,
                    target: outputFormat
                )
            }
            converter = c
        } else {
            converter = nil
        }

        let frameCount = bufferFrameCount
        let format = outputFormat
        let logger = self.logger

        // Calculate how long each buffer represents in wall-clock time so
        // we can pace delivery to real-time.
        let bufferDurationNanoseconds = UInt64(
            Double(frameCount) / format.sampleRate * 1_000_000_000
        )

        deliveryTask = Task.detached { [weak self] in
            do {
                while !Task.isCancelled && audioFile.framePosition < audioFile.length {
                    let remainingFrames = AVAudioFrameCount(audioFile.length - audioFile.framePosition)
                    let framesToRead = min(frameCount, remainingFrames)

                    guard let sourceBuffer = AVAudioPCMBuffer(
                        pcmFormat: sourceFormat,
                        frameCapacity: framesToRead
                    ) else {
                        logger.error("Failed to allocate source buffer")
                        break
                    }

                    try audioFile.read(into: sourceBuffer, frameCount: framesToRead)

                    let deliverBuffer: AVAudioPCMBuffer

                    if let converter {
                        // Convert from source format to output format.
                        let outputFrameCapacity = AVAudioFrameCount(
                            ceil(
                                Double(sourceBuffer.frameLength) * format.sampleRate
                                    / sourceFormat.sampleRate
                            )
                        )
                        guard let outputBuffer = AVAudioPCMBuffer(
                            pcmFormat: format,
                            frameCapacity: outputFrameCapacity
                        ) else {
                            logger.error("Failed to allocate output buffer")
                            break
                        }

                        var error: NSError?
                        nonisolated(unsafe) var allConsumed = false
                        nonisolated(unsafe) let inputBuffer = sourceBuffer
                        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                            if allConsumed {
                                outStatus.pointee = .noDataNow
                                return nil
                            }
                            outStatus.pointee = .haveData
                            allConsumed = true
                            return inputBuffer
                        }

                        if let error {
                            logger.error("Audio conversion failed: \(error.localizedDescription, privacy: .public)")
                            break
                        }

                        deliverBuffer = outputBuffer
                    } else {
                        deliverBuffer = sourceBuffer
                    }

                    handler(deliverBuffer)

                    // Pace delivery to real-time.
                    try await Task.sleep(nanoseconds: bufferDurationNanoseconds)
                }
            } catch is CancellationError {
                // Normal shutdown — nothing to report.
            } catch {
                logger.error("File replay failed: \(error.localizedDescription, privacy: .public)")
            }

            logger.info("File replay finished for \(self?.fileURL.lastPathComponent ?? "unknown", privacy: .public)")
        }
    }

    public func stop() {
        deliveryTask?.cancel()
        deliveryTask = nil
    }
}

// MARK: - Errors

public enum FileAudioReplayerError: LocalizedError {
    case formatConversionUnavailable(source: AVAudioFormat, target: AVAudioFormat)

    public var errorDescription: String? {
        switch self {
        case .formatConversionUnavailable(let source, let target):
            "Cannot convert audio from \(source) to \(target)."
        }
    }
}
