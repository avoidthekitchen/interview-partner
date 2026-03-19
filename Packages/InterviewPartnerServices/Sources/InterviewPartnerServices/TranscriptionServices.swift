import AVFoundation
import FluidAudio
import Foundation
import InterviewPartnerDomain
import OSLog
import Speech

public enum TranscriptionServiceEvent: Sendable {
    case partialText(String)
    case finalizedTurn(TranscriptTurn)
    case transcriptGap(TranscriptGap)
    case diarizationSnapshot(DiarizationSnapshot)
    case limitedModeChanged(isLimited: Bool, message: String?)
}

public struct TranscriptionStopResult: Sendable {
    public let reconciledTurns: [TranscriptTurn]
    public let diarizationSnapshot: DiarizationSnapshot?
    public let diarizationAvailable: Bool
    public let limitedModeMessage: String?

    public init(
        reconciledTurns: [TranscriptTurn],
        diarizationSnapshot: DiarizationSnapshot?,
        diarizationAvailable: Bool,
        limitedModeMessage: String?
    ) {
        self.reconciledTurns = reconciledTurns
        self.diarizationSnapshot = diarizationSnapshot
        self.diarizationAvailable = diarizationAvailable
        self.limitedModeMessage = limitedModeMessage
    }
}

@MainActor
public protocol TranscriptionService: AnyObject {
    func setEventHandler(_ handler: @escaping @Sendable (TranscriptionServiceEvent) -> Void)
    func start(sessionID: UUID, startedAt: Date) async throws
    func stop() async -> TranscriptionStopResult
}

public enum TranscriptionServiceError: LocalizedError {
    case speechRecognizerUnavailable
    case speechRecognizerRequiresServer

    public var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            "Speech recognition is unavailable on this device."
        case .speechRecognizerRequiresServer:
            "On-device speech recognition is unavailable on this device."
        }
    }
}

@MainActor
public final class DefaultTranscriptionService: TranscriptionService {
    private enum Constants {
        static let eouDebounceMs = 640
        static let gapThresholdSeconds = 10.0
    }

    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "DefaultTranscriptionService"
    )
    private let chunkSize: StreamingChunkSize
    private let audioEngine = AVAudioEngine()
    private let asrManager: StreamingEouAsrManager
    private let diarizationEngine: LiveDiarizationEngine
    private let vadEngine = StreamingVadEngine()
    private let speechFallback = SpeechFallbackTranscriptionEngine()
    private let sessionAudioCapture = SessionAudioCapture()
    private let offlineReconciler: OfflineDiarizationReconciler
    private let tuning: DiarizationTuning

    private var hasLoadedModels = false
    private var callbacksConfigured = false
    private var eventHandler: (@Sendable (TranscriptionServiceEvent) -> Void)?
    private var sessionID: UUID?
    private var startedAt: Date?
    private var deltaAccumulator = TranscriptDeltaAccumulator()
    private var vadBoundaryTracker = VadBoundaryTracker()
    private var liveTurns: [TranscriptTurn] = []
    private var liveGaps: [TranscriptGap] = []
    private var lastTurnEndTimeSeconds: TimeInterval?
    private var usingSpeechFallback = false
    private var diarizationAvailable = true
    private var vadAvailable = true
    private var limitedModeMessage: String?
    private var audioTapWorkTracker = AudioTapWorkTracker()
    private var partialCallbackCount = 0
    private var eouCallbackCount = 0
    private var finalizedTurnCount = 0
    private var vadEventCount = 0

    public init(
        chunkSize: StreamingChunkSize = .ms160,
        diarizationConfig: SortformerConfig = .default,
        tuning: DiarizationTuning = .productionDefault
    ) {
        self.chunkSize = chunkSize
        self.tuning = DiarizationTuning(
            name: tuning.name,
            sortformerConfig: diarizationConfig,
            sortformerPostProcessing: tuning.sortformerPostProcessing,
            minimumDominantOverlapSeconds: tuning.minimumDominantOverlapSeconds,
            dominantSpeakerRatioThreshold: tuning.dominantSpeakerRatioThreshold
        )
        asrManager = StreamingEouAsrManager(
            chunkSize: chunkSize,
            eouDebounceMs: Constants.eouDebounceMs
        )
        diarizationEngine = LiveDiarizationEngine(tuning: self.tuning)
        offlineReconciler = OfflineDiarizationReconciler(tuning: self.tuning)
    }

    public func setEventHandler(_ handler: @escaping @Sendable (TranscriptionServiceEvent) -> Void) {
        eventHandler = handler
    }

    public func start(sessionID: UUID, startedAt: Date) async throws {
        self.sessionID = sessionID
        self.startedAt = startedAt
        deltaAccumulator.reset()
        vadBoundaryTracker.reset()
        liveTurns.removeAll()
        liveGaps.removeAll()
        lastTurnEndTimeSeconds = nil
        usingSpeechFallback = false
        diarizationAvailable = true
        vadAvailable = true
        limitedModeMessage = nil
        audioTapWorkTracker = AudioTapWorkTracker()
        partialCallbackCount = 0
        eouCallbackCount = 0
        finalizedTurnCount = 0
        vadEventCount = 0
        try? await sessionAudioCapture.cleanup()

        try await configureCallbacksIfNeeded()

        do {
            try await startFluidAudioSession()
        } catch {
            logger.error("FluidAudio start failed, falling back to Speech: \(error.localizedDescription, privacy: .public)")
            try await startSpeechFallbackSession()
        }
    }

    public func stop() async -> TranscriptionStopResult {
        stopAudioEngine()
        let trackerSnapshotBeforeDrain = audioTapWorkTracker.snapshot()
        logger.info(
            """
            Stopping transcription session. Partial callbacks: \(self.partialCallbackCount, privacy: .public), \
            EOU callbacks: \(self.eouCallbackCount, privacy: .public), \
            finalized turns: \(self.finalizedTurnCount, privacy: .public), \
            VAD events: \(self.vadEventCount, privacy: .public), \
            audio buffers enqueued: \(trackerSnapshotBeforeDrain.enqueuedBuffers, privacy: .public), \
            completed: \(trackerSnapshotBeforeDrain.completedBuffers, privacy: .public), \
            pending: \(trackerSnapshotBeforeDrain.pendingBuffers, privacy: .public)
            """
        )
        await audioTapWorkTracker.waitUntilIdle()
        let trackerSnapshotAfterDrain = audioTapWorkTracker.snapshot()
        logger.info(
            """
            Audio tap drained before finalization. Buffers enqueued: \(trackerSnapshotAfterDrain.enqueuedBuffers, privacy: .public), \
            completed: \(trackerSnapshotAfterDrain.completedBuffers, privacy: .public), \
            pending: \(trackerSnapshotAfterDrain.pendingBuffers, privacy: .public)
            """
        )
        let tempAudioURL = await sessionAudioCapture.stop()
        defer {
            Task {
                try? await sessionAudioCapture.cleanup()
            }
        }

        if usingSpeechFallback {
            await speechFallback.stop()
            let finalTurns = liveTurns.map { turn in
                var reconciled = turn
                reconciled.speakerLabel = "Speaker A"
                reconciled.speakerLabelIsProvisional = false
                return reconciled
            }
            return TranscriptionStopResult(
                reconciledTurns: finalTurns,
                diarizationSnapshot: nil,
                diarizationAvailable: false,
                limitedModeMessage: limitedModeMessage
            )
        }

        do {
            let transcript = try await asrManager.finish()
            logger.info(
                "ASR finish returned transcript with \(transcript.count, privacy: .public) characters"
            )
            await appendIfNeeded(fromCumulativeTranscript: transcript)
            await asrManager.reset()
        } catch {
            logger.error("Failed to finish ASR stream: \(error.localizedDescription, privacy: .public)")
        }

        let snapshot: DiarizationSnapshot?
        let reconciledTurns: [TranscriptTurn]
        if diarizationAvailable {
            snapshot = await diarizationEngine.finalizeAndSnapshot()
            let liveReconciledTurns = LiveTurnAssembler.reconcileTurns(
                snapshot: snapshot,
                turns: liveTurns,
                tuning: tuning
            )
            let offlineResult = await offlineReconciler.reconcile(
                turns: liveTurns,
                audioURL: tempAudioURL
            )
            reconciledTurns = offlineResult.usedOfflineDiarization
                ? offlineResult.turns
                : liveReconciledTurns
        } else {
            snapshot = nil
            let offlineResult = await offlineReconciler.reconcile(
                turns: liveTurns,
                audioURL: tempAudioURL
            )
            reconciledTurns = offlineResult.usedOfflineDiarization ? offlineResult.turns : liveTurns.map {
                var turn = $0
                turn.speakerLabel = "Speaker A"
                turn.speakerLabelIsProvisional = false
                turn.speakerMatchConfidence = nil
                return turn
            }
        }

        if let snapshot {
            emit(.diarizationSnapshot(snapshot))
        }

        return TranscriptionStopResult(
            reconciledTurns: reconciledTurns,
            diarizationSnapshot: snapshot,
            diarizationAvailable: diarizationAvailable,
            limitedModeMessage: limitedModeMessage
        )
    }

    private func startFluidAudioSession() async throws {
        try await loadModelsIfNeeded()
        await asrManager.reset()
        await diarizationEngine.reset()
        await vadEngine.reset()

        do {
            try await diarizationEngine.prepareIfNeeded()
            diarizationAvailable = true
            limitedModeMessage = nil
        } catch {
            diarizationAvailable = false
            limitedModeMessage = "Limited transcription mode: FluidAudio transcription is active, but live speaker diarization is unavailable."
        }

        do {
            try await vadEngine.prepareIfNeeded()
            vadAvailable = true
        } catch {
            vadAvailable = false
            logger.error("Streaming VAD unavailable: \(error.localizedDescription, privacy: .public)")
        }

        emit(
            .limitedModeChanged(
                isLimited: !diarizationAvailable,
                message: limitedModeMessage
            )
        )

        try configureAudioSession()
        try await startAudioEngine(withDiarization: diarizationAvailable)
    }

    private func startSpeechFallbackSession() async throws {
        usingSpeechFallback = true
        diarizationAvailable = false
        limitedModeMessage = "Limited transcription mode: using Speech fallback without speaker diarization."

        emit(.limitedModeChanged(isLimited: true, message: limitedModeMessage))

        try configureAudioSession()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        try await speechFallback.start(audioEngine: audioEngine, format: format) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSpeechFallbackEvent(event)
            }
        }
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

    private func startAudioEngine(withDiarization: Bool) async throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let asrManager = self.asrManager
        let diarizationEngine = self.diarizationEngine
        guard let sessionID else { return }

        try await sessionAudioCapture.start(sessionID: sessionID, format: format)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2048,
            format: format,
            block: AudioTapBridge.makeBlock(
                asrManager: asrManager,
                diarizationEngine: withDiarization ? diarizationEngine : nil,
                vadEngine: vadAvailable ? vadEngine : nil,
                sessionAudioCapture: sessionAudioCapture,
                workTracker: audioTapWorkTracker,
                onVadEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleVadBoundaryEvent(event)
                    }
                }
            )
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
        partialCallbackCount += 1
        let delta = deltaAccumulator.deltaText(from: transcript)
        if partialCallbackCount == 1 || partialCallbackCount.isMultiple(of: 25) {
            logger.debug(
                "Received partial callback #\(self.partialCallbackCount, privacy: .public). Transcript chars: \(transcript.count, privacy: .public), delta chars: \(delta.count, privacy: .public)"
            )
        }
        emit(.partialText(delta))
    }

    private func appendIfNeeded(fromCumulativeTranscript transcript: String) async {
        eouCallbackCount += 1
        let newText = deltaAccumulator.commit(transcript)
        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        emit(.partialText(""))

        guard
            let sessionID,
            let startedAt,
            !trimmedText.isEmpty
        else {
            logger.debug(
                "Ignoring empty EOU callback #\(self.eouCallbackCount, privacy: .public). Transcript chars: \(transcript.count, privacy: .public), delta chars: \(newText.count, privacy: .public)"
            )
            return
        }

        let window: UtteranceWindow
        if vadAvailable {
            let result = vadBoundaryTracker.consumeBestWindow(
                audioDurationSeconds: await currentAudioDurationSeconds(startedAt: startedAt),
                previousBoundarySeconds: lastTurnEndTimeSeconds ?? 0,
                eouDebounceMs: Constants.eouDebounceMs
            )
            window = result.window
            if result.missedSpeechEnd {
                logger.debug(
                    "EOU finalization arrived without a matching VAD speechEnd at \(window.endSeconds, privacy: .public)s"
                )
            }
        } else {
            window = VadBoundaryTracker.fallbackWindow(
                previousBoundarySeconds: lastTurnEndTimeSeconds ?? 0,
                audioDurationSeconds: await currentAudioDurationSeconds(startedAt: startedAt),
                eouDebounceMs: Constants.eouDebounceMs
            )
        }

        let diarizationSegments = diarizationAvailable
            ? await diarizationEngine.currentSnapshot().segments
            : []
        let assembly = LiveTurnAssembler.assembleTurn(
            sessionID: sessionID,
            startedAt: startedAt,
            previousTurnEndTimeSeconds: lastTurnEndTimeSeconds,
            text: trimmedText,
            diarizationAvailable: diarizationAvailable,
            window: window,
            diarizationSegments: diarizationSegments,
            gapThresholdSeconds: Constants.gapThresholdSeconds,
            tuning: tuning
        )

        if let gap = assembly.gap {
            liveGaps.append(gap)
            emit(.transcriptGap(gap))
        }

        liveTurns.append(assembly.turn)
        lastTurnEndTimeSeconds = assembly.turn.endTimeSeconds
        finalizedTurnCount += 1
        logger.info(
            """
            Finalized turn #\(self.finalizedTurnCount, privacy: .public) from EOU callback #\(self.eouCallbackCount, privacy: .public). \
            Window: \(assembly.turn.startTimeSeconds ?? -1, privacy: .public)s -> \(assembly.turn.endTimeSeconds ?? -1, privacy: .public)s, \
            text chars: \(trimmedText.count, privacy: .public), speaker: \(assembly.turn.speakerLabel, privacy: .public)
            """
        )

        emit(.finalizedTurn(assembly.turn))
        if diarizationAvailable {
            emit(.diarizationSnapshot(await diarizationEngine.currentSnapshot()))
        }
    }

    private func handleSpeechFallbackEvent(_ event: SpeechFallbackEvent) {
        switch event {
        case .partial(let text):
            emit(.partialText(text))
        case .final(let text):
            Task {
                await appendIfNeeded(fromCumulativeTranscript: text)
            }
        }
    }

    private func handleVadBoundaryEvent(_ event: VadBoundaryEvent) {
        vadEventCount += 1
        logger.debug(
            "VAD event #\(self.vadEventCount, privacy: .public): \(String(describing: event.kind), privacy: .public) at \(event.timeSeconds, privacy: .public)s"
        )
        vadBoundaryTracker.ingest(event: event)
    }

    private func currentAudioDurationSeconds(startedAt: Date) async -> Double {
        if vadAvailable {
            return max(await vadEngine.currentAudioDurationSeconds(), Date.now.timeIntervalSince(startedAt))
        }
        if diarizationAvailable {
            return max(await diarizationEngine.currentSnapshot().totalAudioSeconds, Date.now.timeIntervalSince(startedAt))
        }
        return Date.now.timeIntervalSince(startedAt)
    }

    private func emit(_ event: TranscriptionServiceEvent) {
        eventHandler?(event)
    }

    private static func defaultModelsDirectory(for chunkSize: StreamingChunkSize) -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return applicationSupportURL
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
            .appendingPathComponent(chunkSize.modelSubdirectory, isDirectory: true)
    }

    private static func downloadModelsIfNeeded(
        to destination: URL,
        chunkSize: StreamingChunkSize
    ) async throws {
        let requiredModels = ModelNames.ParakeetEOU.requiredModels
        let modelsExist = requiredModels.allSatisfy { modelName in
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(modelName).path
            )
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

actor LiveDiarizationEngine {
    private let audioConverter = AudioConverter()
    private let diarizer: SortformerDiarizer

    private var hasLoadedModels = false
    private var totalSamples = 0

    init(tuning: DiarizationTuning = .productionDefault) {
        diarizer = SortformerDiarizer(
            config: tuning.sortformerConfig,
            postProcessingConfig: tuning.sortformerPostProcessing
        )
    }

    func prepareIfNeeded() async throws {
        guard !hasLoadedModels else { return }

        let models = try await SortformerModels.loadFromHuggingFace(config: diarizer.config)
        diarizer.initialize(models: models)
        hasLoadedModels = true
    }

    func reset() {
        diarizer.reset()
        totalSamples = 0
    }

    func ingest(_ buffer: AVAudioPCMBuffer) throws {
        let samples = try audioConverter.resampleBuffer(buffer)
        totalSamples += samples.count
        _ = try diarizer.processSamples(samples)
    }

    func finalizeAndSnapshot() -> DiarizationSnapshot {
        diarizer.timeline.finalize()
        return snapshot(includeTentative: false)
    }

    func currentSnapshot() -> DiarizationSnapshot {
        snapshot(includeTentative: true)
    }

    private func snapshot(includeTentative: Bool) -> DiarizationSnapshot {
        let finalizedSegments = diarizer.timeline.segments.enumerated().flatMap { speakerIndex, segments in
            segments.map { segment in
                DiarizedSegment(
                    speakerIndex: speakerIndex,
                    startTimeSeconds: TimeInterval(segment.startTime),
                    endTimeSeconds: TimeInterval(segment.endTime),
                    isFinal: true
                )
            }
        }

        let tentativeSegments: [DiarizedSegment]
        if includeTentative {
            tentativeSegments = diarizer.timeline.tentativeSegments.enumerated().flatMap { speakerIndex, segments in
                segments.map { segment in
                    DiarizedSegment(
                        speakerIndex: speakerIndex,
                        startTimeSeconds: TimeInterval(segment.startTime),
                        endTimeSeconds: TimeInterval(segment.endTime),
                        isFinal: false
                    )
                }
            }
        } else {
            tentativeSegments = []
        }

        let allSegments = (finalizedSegments + tentativeSegments)
            .sorted { lhs, rhs in
                if lhs.startTimeSeconds == rhs.startTimeSeconds {
                    return lhs.speakerIndex < rhs.speakerIndex
                }
                return lhs.startTimeSeconds < rhs.startTimeSeconds
            }

        return DiarizationSnapshot(
            totalAudioSeconds: Double(totalSamples) / 16_000.0,
            segments: allSegments,
            attributedSpeakerCount: Set(allSegments.map(\.speakerIndex)).count
        )
    }
}

private enum SpeechFallbackEvent: Sendable {
    case partial(String)
    case final(String)
}

@MainActor
private final class SpeechFallbackTranscriptionEngine {
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var handler: (@Sendable (SpeechFallbackEvent) -> Void)?

    func start(
        audioEngine: AVAudioEngine,
        format: AVAudioFormat,
        handler: @escaping @Sendable (SpeechFallbackEvent) -> Void
    ) async throws {
        self.handler = handler

        let authStatus = await Self.requestSpeechAuthorization()
        guard authStatus == .authorized else {
            throw TranscriptionServiceError.speechRecognizerUnavailable
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionServiceError.speechRecognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionServiceError.speechRecognizerRequiresServer
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            if result.isFinal {
                self.handler?(.final(result.bestTranscription.formattedString))
            } else {
                self.handler?(.partial(result.bestTranscription.formattedString))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() async {
        request?.endAudio()
        task?.finish()
        task?.cancel()
        task = nil
        request = nil
        handler = nil
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copiedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameLength
        ) else {
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
    private static let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "AudioTap"
    )

    nonisolated static func makeBlock(
        asrManager: StreamingEouAsrManager,
        diarizationEngine: LiveDiarizationEngine?,
        vadEngine: StreamingVadEngine?,
        sessionAudioCapture: SessionAudioCapture,
        workTracker: AudioTapWorkTracker,
        onVadEvent: @escaping @Sendable (VadBoundaryEvent) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let bufferBox = buffer.deepCopy().map(SendablePCMBufferBox.init) else { return }
            workTracker.begin()

            Task {
                defer {
                    workTracker.end()
                }
                do {
                    _ = try await asrManager.process(audioBuffer: bufferBox.buffer)
                    try await sessionAudioCapture.append(bufferBox.buffer)
                    if let diarizationEngine {
                        try await diarizationEngine.ingest(bufferBox.buffer)
                    }
                    if let vadEngine {
                        let events = try await vadEngine.ingest(bufferBox.buffer)
                        for event in events {
                            onVadEvent(event)
                        }
                    }
                } catch {
                    logger.error(
                        "Audio processing failed: \(error.localizedDescription, privacy: .public)"
                    )
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

struct AudioTapWorkTrackerSnapshot: Sendable {
    let enqueuedBuffers: Int
    let completedBuffers: Int

    var pendingBuffers: Int {
        enqueuedBuffers - completedBuffers
    }
}

final class AudioTapWorkTracker: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var enqueuedBuffers = 0
    private var completedBuffers = 0

    func begin() {
        lock.lock()
        enqueuedBuffers += 1
        lock.unlock()
        group.enter()
    }

    func end() {
        lock.lock()
        completedBuffers += 1
        lock.unlock()
        group.leave()
    }

    func snapshot() -> AudioTapWorkTrackerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return AudioTapWorkTrackerSnapshot(
            enqueuedBuffers: enqueuedBuffers,
            completedBuffers: completedBuffers
        )
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [group] in
                group.wait()
                continuation.resume()
            }
        }
    }
}
