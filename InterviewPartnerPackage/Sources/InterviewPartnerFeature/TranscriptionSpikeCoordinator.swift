import AVFoundation
import FluidAudio
import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class TranscriptionSpikeCoordinator {
    public private(set) var partialText = ""
    public private(set) var turns: [TranscriptTurn] = []
    public private(set) var isRecording = false
    public private(set) var statusMessage = "Ready to start"
    public private(set) var errorMessage: String?

    private let chunkSize: StreamingChunkSize = .ms160
    private let audioEngine = AVAudioEngine()
    private let asrManager = StreamingEouAsrManager(chunkSize: .ms160)
    private var hasLoadedModels = false
    private var callbacksConfigured = false
    private var persistenceSink: ((TranscriptTurnRecord) -> Void)?
    private var lastCommittedTranscript = ""

    public init() {}

    public func configurePersistence(_ sink: @escaping (TranscriptTurnRecord) -> Void) {
        persistenceSink = sink
    }

    public func toggleRecording() {
        if isRecording {
            stopIfNeeded()
        } else {
            Task {
                await start()
            }
        }
    }

    public func stopIfNeeded() {
        guard isRecording else { return }

        Task {
            await stop()
        }
    }

    private func start() async {
        errorMessage = nil
        partialText = ""
        turns.removeAll()
        lastCommittedTranscript = ""
        statusMessage = "Preparing microphone and models..."

        do {
            try await configureCallbacksIfNeeded()
            try await loadModelsIfNeeded()
            await asrManager.reset()
            try configureAudioSession()
            try startAudioEngine()
            isRecording = true
            statusMessage = "Listening for speech..."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Unable to start transcription"
            stopAudioEngine()
        }
    }

    private func stop() async {
        stopAudioEngine()

        do {
            let transcript = try await asrManager.finish()
            appendIfNeeded(fromCumulativeTranscript: transcript)
            await asrManager.reset()
            statusMessage = "Stopped"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Stopped with an error"
        }

        partialText = ""
        isRecording = false
    }

    private func configureCallbacksIfNeeded() async throws {
        guard !callbacksConfigured else { return }

        await asrManager.setPartialCallback { [weak self] transcript in
            Task { @MainActor [weak self] in
                self?.handlePartialTranscript(transcript)
            }
        }

        await asrManager.setEouCallback { [weak self] transcript in
            Task { @MainActor [weak self] in
                self?.appendIfNeeded(fromCumulativeTranscript: transcript)
            }
        }

        callbacksConfigured = true
    }

    private func loadModelsIfNeeded() async throws {
        guard !hasLoadedModels else { return }
        statusMessage = "Downloading/loading FluidAudio models..."
        let modelDirectory = Self.defaultModelsDirectory(for: chunkSize)
        try await Self.downloadModelsIfNeeded(to: modelDirectory, chunkSize: chunkSize)
        try await asrManager.loadModels(modelDir: modelDirectory)
        hasLoadedModels = true
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)
        #endif
    }

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let asrManager = self.asrManager

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2048,
            format: format,
            block: AudioTapBridge.makeBlock(asrManager: asrManager)
        )

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudioEngine() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    private func handlePartialTranscript(_ transcript: String) {
        partialText = deltaText(fromCumulativeTranscript: transcript)
        if isRecording {
            statusMessage = partialText.isEmpty ? "Listening for speech..." : "Receiving partial text..."
        }
    }

    private func appendIfNeeded(fromCumulativeTranscript transcript: String) {
        let newText = deltaText(fromCumulativeTranscript: transcript)
        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        lastCommittedTranscript = transcript
        partialText = ""

        guard !trimmedText.isEmpty else { return }

        let turn = TranscriptTurn(text: trimmedText)
        turns.append(turn)
        persistenceSink?(TranscriptTurnRecord(id: turn.id, text: turn.text, createdAt: turn.createdAt))
        statusMessage = "Finalized turn received"
    }

    private func deltaText(fromCumulativeTranscript transcript: String) -> String {
        guard transcript.hasPrefix(lastCommittedTranscript) else {
            return transcript
        }

        return String(transcript.dropFirst(lastCommittedTranscript.count))
    }

    private static func defaultModelsDirectory(for chunkSize: StreamingChunkSize) -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!

        return applicationSupportURL
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
            .appendingPathComponent(chunkSize.modelSubdirectory, isDirectory: true)
    }

    private static func downloadModelsIfNeeded(to destination: URL, chunkSize: StreamingChunkSize) async throws {
        let requiredModels = ModelNames.ParakeetEOU.requiredModels
        let modelsExist = requiredModels.allSatisfy { modelName in
            FileManager.default.fileExists(atPath: destination.appendingPathComponent(modelName).path)
        }

        guard !modelsExist else { return }

        let modelsRoot = destination.deletingLastPathComponent().deletingLastPathComponent()
        let repo: Repo

        switch chunkSize {
        case .ms160:
            repo = .parakeetEou160
        case .ms320, .ms1600:
            repo = .parakeetEou320
        }

        try await DownloadUtils.downloadRepo(repo, to: modelsRoot)
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copiedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        copiedBuffer.frameLength = frameLength

        let channelCount = Int(format.channelCount)
        let frameLength = Int(self.frameLength)

        if let source = floatChannelData, let destination = copiedBuffer.floatChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copiedBuffer
        }

        if let source = int16ChannelData, let destination = copiedBuffer.int16ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copiedBuffer
        }

        if let source = int32ChannelData, let destination = copiedBuffer.int32ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copiedBuffer
        }

        return nil
    }
}

private enum AudioTapBridge {
    private static let logger = Logger(subsystem: "com.mistercheese.InterviewPartner", category: "AudioTap")

    nonisolated static func makeBlock(asrManager: StreamingEouAsrManager) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let bufferBox = buffer.deepCopy().map(SendablePCMBufferBox.init) else { return }

            Task {
                do {
                    _ = try await asrManager.process(audioBuffer: bufferBox.buffer)
                } catch {
                    logger.error("Audio processing failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

private final class SendablePCMBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
