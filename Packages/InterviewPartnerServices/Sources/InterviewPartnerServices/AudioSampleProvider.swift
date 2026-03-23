import AVFoundation
import OSLog

/// A protocol that abstracts the source of audio samples away from any
/// specific capture mechanism (microphone, file playback, etc.).
///
/// Conformers deliver `AVAudioPCMBuffer` samples to a registered handler
/// and expose the audio format of the delivered buffers.
public protocol AudioSampleProvider: Sendable {
    /// The audio format of buffers delivered by this provider.
    /// Only valid after ``start(handler:)`` has been called.
    var audioFormat: AVAudioFormat { get }

    /// Begin delivering audio buffers. Each captured buffer is forwarded
    /// to `handler` on an unspecified queue. The handler must be safe to
    /// call from any isolation context.
    ///
    /// - Parameter handler: Receives every captured buffer.
    func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws

    /// Stop delivering audio buffers and release capture resources.
    func stop()
}

/// A concrete ``AudioSampleProvider`` that captures audio from the device
/// microphone via `AVAudioEngine`.
public final class MicrophoneAudioProvider: AudioSampleProvider, @unchecked Sendable {
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "MicrophoneAudioProvider"
    )

    private let audioEngine = AVAudioEngine()

    // Lazily resolved on `start` since inputNode format isn't
    // meaningful until the audio session is configured.
    private var resolvedFormat: AVAudioFormat?

    public var audioFormat: AVAudioFormat {
        if let resolvedFormat {
            return resolvedFormat
        }
        return audioEngine.inputNode.outputFormat(forBus: 0)
    }

    /// Direct access to the underlying `AVAudioEngine`.
    ///
    /// This is exposed so that subsystems that need the engine itself
    /// (e.g. `SpeechFallbackTranscriptionEngine`) can install their own
    /// tap and start/stop the engine via a separate code-path.
    /// Prefer using the ``AudioSampleProvider`` API whenever possible.
    public var engine: AVAudioEngine { audioEngine }

    public init() {}

    public func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        configureAudioSession()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        resolvedFormat = format

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            handler(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    public func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        deactivateAudioSession()
    }

    // MARK: - Private

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }
}
