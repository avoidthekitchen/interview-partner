import AVFoundation
import FluidAudio
import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class TranscriptionSpikeCoordinator {
    private static let eouDebounceMs = 640
    private static let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "TranscriptionSpikeCoordinator"
    )

    public private(set) var partialText = ""
    public private(set) var turns: [TranscriptTurn] = []
    public private(set) var diarizedSegments: [DiarizedSegment] = []
    public private(set) var isRecording = false
    public private(set) var statusMessage = "Ready to start"
    public private(set) var diarizationStatusMessage = "Sortformer diarization not started"
    public private(set) var sprintRecommendation = "Pending: start the spike to evaluate whether live speaker labels are viable."
    public private(set) var errorMessage: String?

    private let chunkSize: StreamingChunkSize = .ms160
    private let audioEngine = AVAudioEngine()
    private let asrManager = StreamingEouAsrManager(
        chunkSize: .ms160,
        eouDebounceMs: TranscriptionSpikeCoordinator.eouDebounceMs
    )
    private let diarizationEngine = LiveDiarizationSpikeEngine()
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
        diarizedSegments.removeAll()
        lastCommittedTranscript = ""
        statusMessage = "Preparing microphone and models..."
        sprintRecommendation = "Running live ASR + Sortformer diarization spike."

        do {
            try await configureCallbacksIfNeeded()
            try await loadModelsIfNeeded()
            await asrManager.reset()
            await diarizationEngine.reset()

            do {
                diarizationStatusMessage = "Loading Sortformer diarization model..."
                Self.logger.info("Preparing Sortformer diarization model for live speaker mapping")
                try await diarizationEngine.prepareIfNeeded()
                diarizationStatusMessage = "Sortformer diarization active on the shared microphone stream."
                Self.logger.info("Sortformer diarization model ready; live speaker mapping is active")
            } catch {
                diarizationStatusMessage =
                    "Sortformer diarization failed to load. Sprint 2 should fall back to unlabeled live turns unless this improves."
                Self.logger.error(
                    "Sortformer diarization model failed to load; continuing without live labels: \(error.localizedDescription, privacy: .public)"
                )
            }

            try configureAudioSession()
            try startAudioEngine()
            isRecording = true
            statusMessage = "Listening for speech with shorter EOU debounce..."
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
            await appendIfNeeded(fromCumulativeTranscript: transcript)
            await asrManager.reset()
            statusMessage = "Stopped"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Stopped with an error"
        }

        let diarizationSnapshot = await diarizationEngine.finalizeAndSnapshot()
        diarizedSegments = diarizationSnapshot.segments
        refreshSprintRecommendation(from: diarizationSnapshot)
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
                await self?.appendIfNeeded(fromCumulativeTranscript: transcript)
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
        let diarizationEngine = self.diarizationEngine

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2048,
            format: format,
            block: AudioTapBridge.makeBlock(asrManager: asrManager, diarizationEngine: diarizationEngine)
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

    private func appendIfNeeded(fromCumulativeTranscript transcript: String) async {
        let newText = deltaText(fromCumulativeTranscript: transcript)
        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        lastCommittedTranscript = transcript
        partialText = ""

        guard !trimmedText.isEmpty else { return }

        let attribution = await diarizationEngine.attributeNextTurn(
            eouDebounceMs: Self.eouDebounceMs
        )
        let turn = TranscriptTurn(
            speakerLabel: attribution.speakerLabel,
            text: trimmedText,
            startTimeSeconds: attribution.estimatedStartTimeSeconds,
            endTimeSeconds: attribution.estimatedEndTimeSeconds,
            speakerMatchConfidence: attribution.confidence
        )
        turns.append(turn)
        persistenceSink?(
            TranscriptTurnRecord(
                id: turn.id,
                speakerLabel: turn.speakerLabel,
                text: turn.text,
                createdAt: turn.createdAt,
                startTimeSeconds: turn.startTimeSeconds,
                endTimeSeconds: turn.endTimeSeconds,
                speakerMatchConfidence: turn.speakerMatchConfidence
            )
        )

        let diarizationSnapshot = await diarizationEngine.currentSnapshot()
        diarizedSegments = diarizationSnapshot.segments
        diarizationStatusMessage = attribution.note
        refreshSprintRecommendation(from: diarizationSnapshot)
        statusMessage = "Finalized turn mapped onto diarization timeline"
        Self.logger.info(
            "Finalized turn \(turn.id.uuidString, privacy: .public) label=\(turn.speakerLabel, privacy: .public) confidence=\(attribution.confidence, format: .fixed(precision: 2)) window=\(Self.windowSummary(start: attribution.estimatedStartTimeSeconds, end: attribution.estimatedEndTimeSeconds), privacy: .public) textLength=\(turn.text.count) diarizationSegments=\(diarizationSnapshot.segments.count) note=\(attribution.note, privacy: .public)"
        )
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

    private func refreshSprintRecommendation(from snapshot: DiarizationSnapshot) {
        let mappedTurns = turns.filter { $0.speakerLabel != "Unclear" }.count
        let lowConfidenceTurns = turns.filter { ($0.speakerMatchConfidence ?? 0) < 0.55 }.count

        if mappedTurns == 0 {
            sprintRecommendation =
                "Recommendation: live speaker labels are not yet viable. The spike is capturing audio and diarization segments, but finalized turns are still effectively unlabeled."
            return
        }

        if mappedTurns == turns.count && lowConfidenceTurns <= max(1, turns.count / 4) {
            sprintRecommendation =
                "Recommendation: live speaker labels look technically viable for Sprint 2, but only through a shared-audio timestamp mapping layer. The ASR API still does not provide speaker IDs or turn timestamps directly."
            return
        }

        sprintRecommendation =
            "Recommendation: keep the mapping spike as evidence, but plan for a fallback to unlabeled live turns in v1 if real-device validation is noisy. Current run mapped \(mappedTurns)/\(turns.count) turns across \(snapshot.segments.count) diarization segments."
    }

    private static func windowSummary(start: TimeInterval, end: TimeInterval) -> String {
        String(format: "%.2fs-%.2fs", start, end)
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

    nonisolated static func makeBlock(
        asrManager: StreamingEouAsrManager,
        diarizationEngine: LiveDiarizationSpikeEngine
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let bufferBox = buffer.deepCopy().map(SendablePCMBufferBox.init) else { return }

            Task {
                do {
                    try await diarizationEngine.ingest(bufferBox.buffer)
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
