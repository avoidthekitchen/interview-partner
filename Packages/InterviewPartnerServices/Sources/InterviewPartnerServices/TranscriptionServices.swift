import AVFoundation
import FluidAudio
import Foundation
import InterviewPartnerDomain
import OSLog
import Speech

public struct DiarizedSegment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let speakerIndex: Int
    public let startTimeSeconds: TimeInterval
    public let endTimeSeconds: TimeInterval
    public let isFinal: Bool

    public init(
        id: UUID = UUID(),
        speakerIndex: Int,
        startTimeSeconds: TimeInterval,
        endTimeSeconds: TimeInterval,
        isFinal: Bool
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.isFinal = isFinal
    }
}

public struct DiarizationSnapshot: Hashable, Sendable {
    public let totalAudioSeconds: Double
    public let segments: [DiarizedSegment]
    public let attributedSpeakerCount: Int

    public init(
        totalAudioSeconds: Double,
        segments: [DiarizedSegment],
        attributedSpeakerCount: Int
    ) {
        self.totalAudioSeconds = totalAudioSeconds
        self.segments = segments
        self.attributedSpeakerCount = attributedSpeakerCount
    }
}

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
    private let audioProvider: any AudioSampleProvider
    private let asrManager: StreamingEouAsrManager
    private let diarizationEngine: LiveDiarizationEngine
    private let speechFallback = SpeechFallbackTranscriptionEngine()

    private var hasLoadedModels = false
    private var callbacksConfigured = false
    private var eventHandler: (@Sendable (TranscriptionServiceEvent) -> Void)?
    private var sessionID: UUID?
    private var startedAt: Date?
    private var lastCommittedTranscript = ""
    private var liveTurns: [TranscriptTurn] = []
    private var liveGaps: [TranscriptGap] = []
    private var lastTurnEndTimeSeconds: TimeInterval?
    private var usingSpeechFallback = false
    private var diarizationAvailable = true
    private var limitedModeMessage: String?

    public init(
        audioProvider: some AudioSampleProvider = MicrophoneAudioProvider(),
        chunkSize: StreamingChunkSize = .ms160,
        diarizationConfig: SortformerConfig = .default
    ) {
        self.audioProvider = audioProvider
        self.chunkSize = chunkSize
        asrManager = StreamingEouAsrManager(
            chunkSize: chunkSize,
            eouDebounceMs: Constants.eouDebounceMs
        )
        diarizationEngine = LiveDiarizationEngine(config: diarizationConfig)
    }

    public func setEventHandler(_ handler: @escaping @Sendable (TranscriptionServiceEvent) -> Void) {
        eventHandler = handler
    }

    public func start(sessionID: UUID, startedAt: Date) async throws {
        self.sessionID = sessionID
        self.startedAt = startedAt
        lastCommittedTranscript = ""
        liveTurns.removeAll()
        liveGaps.removeAll()
        lastTurnEndTimeSeconds = nil
        usingSpeechFallback = false
        diarizationAvailable = true
        limitedModeMessage = nil

        try await configureCallbacksIfNeeded()

        do {
            try await startFluidAudioSession()
        } catch {
            logger.error("FluidAudio start failed, falling back to Speech: \(error.localizedDescription, privacy: .public)")
            try await startSpeechFallbackSession()
        }
    }

    public func stop() async -> TranscriptionStopResult {
        audioProvider.stop()

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
            await appendIfNeeded(fromCumulativeTranscript: transcript)
            await asrManager.reset()
        } catch {
            logger.error("Failed to finish ASR stream: \(error.localizedDescription, privacy: .public)")
        }

        let snapshot: DiarizationSnapshot?
        let reconciledTurns: [TranscriptTurn]
        if diarizationAvailable {
            snapshot = await diarizationEngine.finalizeAndSnapshot()
            reconciledTurns = reconcileTurns(snapshot: snapshot, turns: liveTurns)
        } else {
            snapshot = nil
            reconciledTurns = liveTurns.map {
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

        do {
            try await diarizationEngine.prepareIfNeeded()
            diarizationAvailable = true
            limitedModeMessage = nil
        } catch {
            diarizationAvailable = false
            limitedModeMessage = "Limited transcription mode: FluidAudio transcription is active, but live speaker diarization is unavailable."
        }

        emit(
            .limitedModeChanged(
                isLimited: !diarizationAvailable,
                message: limitedModeMessage
            )
        )

        let asrManager = self.asrManager
        let diarizationEngine = self.diarizationAvailable ? self.diarizationEngine : nil
        try audioProvider.start(
            handler: AudioTapBridge.makeHandler(
                asrManager: asrManager,
                diarizationEngine: diarizationEngine
            )
        )
    }

    private func startSpeechFallbackSession() async throws {
        usingSpeechFallback = true
        diarizationAvailable = false
        limitedModeMessage = "Limited transcription mode: using Speech fallback without speaker diarization."

        emit(.limitedModeChanged(isLimited: true, message: limitedModeMessage))

        guard let micProvider = audioProvider as? MicrophoneAudioProvider else {
            throw TranscriptionServiceError.speechRecognizerUnavailable
        }

        let format = micProvider.audioFormat

        try await speechFallback.start(audioProvider: micProvider, format: format) { [weak self] event in
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

    private func handlePartialTranscript(_ transcript: String) {
        emit(.partialText(deltaText(fromCumulativeTranscript: transcript)))
    }

    private func appendIfNeeded(fromCumulativeTranscript transcript: String) async {
        let newText = deltaText(fromCumulativeTranscript: transcript)
        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        lastCommittedTranscript = transcript
        emit(.partialText(""))

        guard
            let sessionID,
            let startedAt,
            !trimmedText.isEmpty
        else { return }

        let attribution: DiarizationTurnAttribution
        if diarizationAvailable {
            attribution = await diarizationEngine.attributeNextTurn(
                eouDebounceMs: Constants.eouDebounceMs
            )
        } else {
            let now = Date.now
            let elapsed = now.timeIntervalSince(startedAt)
            attribution = DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Speaker A",
                estimatedStartTimeSeconds: lastTurnEndTimeSeconds ?? max(0, elapsed - 1),
                estimatedEndTimeSeconds: elapsed,
                confidence: 0,
                note: "Fallback transcription does not provide diarization."
            )
        }

        if let priorTurnEnd = lastTurnEndTimeSeconds,
           attribution.estimatedStartTimeSeconds - priorTurnEnd >= Constants.gapThresholdSeconds {
            let gap = TranscriptGap(
                sessionID: sessionID,
                startTimestamp: startedAt.addingTimeInterval(priorTurnEnd),
                endTimestamp: startedAt.addingTimeInterval(attribution.estimatedStartTimeSeconds),
                reason: .transcriptionUnavailable
            )
            liveGaps.append(gap)
            emit(.transcriptGap(gap))
        }

        let turn = TranscriptTurn(
            speakerLabel: attribution.speakerLabel,
            text: trimmedText,
            timestamp: startedAt.addingTimeInterval(attribution.estimatedEndTimeSeconds),
            isFinal: true,
            startTimeSeconds: attribution.estimatedStartTimeSeconds,
            endTimeSeconds: attribution.estimatedEndTimeSeconds,
            speakerMatchConfidence: diarizationAvailable ? attribution.confidence : nil,
            speakerLabelIsProvisional: diarizationAvailable
        )
        liveTurns.append(turn)
        lastTurnEndTimeSeconds = attribution.estimatedEndTimeSeconds

        emit(.finalizedTurn(turn))
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

    private func reconcileTurns(
        snapshot: DiarizationSnapshot?,
        turns: [TranscriptTurn]
    ) -> [TranscriptTurn] {
        guard let snapshot else {
            return turns
        }

        // If we have multiple diarization speakers but few turns, split the turns
        let uniqueSpeakers = Set(snapshot.segments.map(\.speakerIndex))
        if uniqueSpeakers.count > 1 && turns.count == 1, let singleTurn = turns.first {
            // Split the single turn by speaker boundaries
            return splitTurnBySpeakers(turn: singleTurn, segments: snapshot.segments.filter(\.isFinal))
        }

        // Original reconciliation for normal cases
        var previousBoundary: TimeInterval = 0
        return turns.map { turn in
            let start = turn.startTimeSeconds ?? previousBoundary
            let end = max(turn.endTimeSeconds ?? start, start)
            let attribution = DominantSpeakerMatcher.attributeTurn(
                segments: snapshot.segments.filter(\.isFinal),
                windowStart: start,
                windowEnd: end,
                speakerLabel: defaultSpeakerLabel(for:)
            )
            previousBoundary = end

            var reconciled = turn
            reconciled.speakerLabel = attribution.speakerLabel
            reconciled.speakerMatchConfidence = attribution.confidence
            reconciled.speakerLabelIsProvisional = false
            return reconciled
        }
    }

    /// Splits a single turn into multiple turns based on speaker changes in diarization segments
    private func splitTurnBySpeakers(turn: TranscriptTurn, segments: [DiarizedSegment]) -> [TranscriptTurn] {
        guard let turnStart = turn.startTimeSeconds,
              let turnEnd = turn.endTimeSeconds,
              !segments.isEmpty else {
            return [turn]
        }

        // Filter segments that overlap with this turn
        let overlappingSegments = segments.filter { segment in
            segment.endTimeSeconds > turnStart && segment.startTimeSeconds < turnEnd
        }.sorted { $0.startTimeSeconds < $1.startTimeSeconds }

        guard overlappingSegments.count > 1 else {
            return [turn]
        }

        // Group consecutive segments by speaker
        var speakerBlocks: [(speakerIndex: Int, start: TimeInterval, end: TimeInterval)] = []
        for segment in overlappingSegments {
            if let last = speakerBlocks.last, last.speakerIndex == segment.speakerIndex {
                // Extend the last block
                speakerBlocks[speakerBlocks.count - 1].end = max(last.end, segment.endTimeSeconds)
            } else {
                speakerBlocks.append((segment.speakerIndex, segment.startTimeSeconds, segment.endTimeSeconds))
            }
        }

        // Split the turn text proportionally by duration
        let words = turn.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let totalDuration = turnEnd - turnStart
        guard totalDuration > 0 else { return [turn] }

        var newTurns: [TranscriptTurn] = []
        var wordIndex = 0

        for block in speakerBlocks {
            let blockDuration = block.end - block.start
            let blockProportion = blockDuration / totalDuration
            let wordCountForBlock = Int(Double(words.count) * blockProportion)

            // Ensure at least one word per block, but don't exceed available words
            let actualWordCount = max(1, min(wordCountForBlock, words.count - wordIndex))
            let blockWords = words[wordIndex..<min(wordIndex + actualWordCount, words.count)]
            wordIndex += actualWordCount

            guard !blockWords.isEmpty else { continue }

            let blockText = blockWords.joined(separator: " ")
            let speakerLabel = defaultSpeakerLabel(for: block.speakerIndex)

            // Calculate timestamp for this block
            let blockMidTime = (block.start + block.end) / 2
            let timestamp = turn.timestamp.addingTimeInterval(blockMidTime - turnEnd)

            newTurns.append(TranscriptTurn(
                speakerLabel: speakerLabel,
                text: blockText,
                timestamp: timestamp,
                isFinal: true,
                startTimeSeconds: max(block.start, turnStart),
                endTimeSeconds: min(block.end, turnEnd),
                speakerMatchConfidence: 1.0, // High confidence since we're using diarization
                speakerLabelIsProvisional: false
            ))
        }

        // Distribute any remaining words to the last turn
        if wordIndex < words.count && !newTurns.isEmpty {
            let remainingWords = words[wordIndex...].joined(separator: " ")
            var lastTurn = newTurns.removeLast()
            lastTurn.text += " " + remainingWords
            newTurns.append(lastTurn)
        }

        return newTurns.isEmpty ? [turn] : newTurns
    }

    private func deltaText(fromCumulativeTranscript transcript: String) -> String {
        guard transcript.hasPrefix(lastCommittedTranscript) else {
            return transcript
        }

        return String(transcript.dropFirst(lastCommittedTranscript.count))
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

private struct DiarizationTurnAttribution: Hashable, Sendable {
    let speakerIndex: Int?
    let speakerLabel: String
    let estimatedStartTimeSeconds: TimeInterval
    let estimatedEndTimeSeconds: TimeInterval
    let confidence: Double
    let note: String
}

private enum DominantSpeakerMatcher {
    static func attributeNextTurn(
        segments: [DiarizedSegment],
        previousBoundarySeconds: TimeInterval,
        audioDurationSeconds: TimeInterval,
        eouDebounceMs: Int,
        speakerLabel: (Int) -> String
    ) -> DiarizationTurnAttribution {
        let estimatedEnd = max(
            previousBoundarySeconds,
            audioDurationSeconds - (Double(eouDebounceMs) / 1000.0)
        )
        return attributeTurn(
            segments: segments,
            windowStart: previousBoundarySeconds,
            windowEnd: estimatedEnd,
            speakerLabel: speakerLabel
        )
    }

    static func attributeTurn(
        segments: [DiarizedSegment],
        windowStart: TimeInterval,
        windowEnd: TimeInterval,
        speakerLabel: (Int) -> String
    ) -> DiarizationTurnAttribution {
        let sanitizedEnd = max(windowEnd, windowStart)
        let windowDuration = max(sanitizedEnd - windowStart, 0.001)

        var overlapBySpeaker: [Int: Double] = [:]
        for segment in segments {
            let overlap = max(
                0,
                min(segment.endTimeSeconds, sanitizedEnd) - max(segment.startTimeSeconds, windowStart)
            )

            guard overlap > 0 else { continue }
            overlapBySpeaker[segment.speakerIndex, default: 0] += overlap
        }

        let rankedSpeakers = overlapBySpeaker.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }

        guard let topSpeaker = rankedSpeakers.first else {
            return DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Unclear",
                estimatedStartTimeSeconds: windowStart,
                estimatedEndTimeSeconds: sanitizedEnd,
                confidence: 0,
                note: "No diarization segment overlapped the turn window."
            )
        }

        let secondOverlap = rankedSpeakers.dropFirst().first?.value ?? 0
        let dominantOverlap = topSpeaker.value
        let confidence = min(1.0, dominantOverlap / windowDuration)

        if dominantOverlap < 0.25 || (secondOverlap > 0 && dominantOverlap / secondOverlap < 1.25) {
            return DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Unclear",
                estimatedStartTimeSeconds: windowStart,
                estimatedEndTimeSeconds: sanitizedEnd,
                confidence: confidence,
                note: "Competing diarization segments overlap this turn window."
            )
        }

        return DiarizationTurnAttribution(
            speakerIndex: topSpeaker.key,
            speakerLabel: speakerLabel(topSpeaker.key),
            estimatedStartTimeSeconds: windowStart,
            estimatedEndTimeSeconds: sanitizedEnd,
            confidence: confidence,
            note: "Mapped from dominant diarization overlap within the turn window."
        )
    }
}

private actor LiveDiarizationEngine {
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "LiveDiarizationEngine"
    )
    private let audioConverter = AudioConverter()
    private let diarizer: SortformerDiarizer

    // Diagnostic logging to stderr for benchmark visibility
    private func logDiagnostic(_ message: String) {
        FileHandle.standardError.write("[DIARIZATION] \(message)\n".data(using: .utf8)!)
    }

    private var hasLoadedModels = false
    private var totalSamples = 0
    private var lastAssignedBoundarySeconds: TimeInterval = 0
    private var speakerLabelsByIndex: [Int: String] = [:]
    private var segmentHistory: [DiarizedSegment] = []

    init(config: SortformerConfig = .default) {
        diarizer = SortformerDiarizer(config: config, postProcessingConfig: .default)
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
        lastAssignedBoundarySeconds = 0
        speakerLabelsByIndex.removeAll()
    }

    func ingest(_ buffer: AVAudioPCMBuffer) throws {
        let samples = try audioConverter.resampleBuffer(buffer)
        totalSamples += samples.count
        _ = try diarizer.processSamples(samples)
    }

    func finalizeAndSnapshot() -> DiarizationSnapshot {
        diarizer.timeline.finalize()
        let snapshot = snapshot(includeTentative: false)

        // DIAGNOSTIC LOGGING
        logDiagnostic("📊 Final Snapshot: \(snapshot.segments.count) segments, \(snapshot.attributedSpeakerCount) speakers")
        logDiagnostic("  Audio duration: \(snapshot.totalAudioSeconds)s")

        // Log segment distribution by speaker
        var segmentsBySpeaker: [Int: Int] = [:]
        for segment in snapshot.segments {
            segmentsBySpeaker[segment.speakerIndex, default: 0] += 1
        }
        for (speakerIndex, count) in segmentsBySpeaker.sorted(by: { $0.key < $1.key }) {
            let totalDuration = snapshot.segments
                .filter { $0.speakerIndex == speakerIndex }
                .reduce(0) { $0 + ($1.endTimeSeconds - $1.startTimeSeconds) }
            logDiagnostic("  Speaker \(speakerIndex): \(count) segments, \(totalDuration)s total")
        }

        return snapshot
    }

    func currentSnapshot() -> DiarizationSnapshot {
        snapshot(includeTentative: true)
    }

    func attributeNextTurn(eouDebounceMs: Int) -> DiarizationTurnAttribution {
        let currentSnapshot = snapshot(includeTentative: true)

        // DIAGNOSTIC LOGGING
        logDiagnostic("📊 Attribution Request: boundary=\(self.lastAssignedBoundarySeconds)s, duration=\(currentSnapshot.totalAudioSeconds)s")
        logDiagnostic("  Total segments: \(currentSnapshot.segments.count), Unique speakers: \(currentSnapshot.attributedSpeakerCount)")

        // Log all segments in the window
        let windowSegments = currentSnapshot.segments.filter { segment in
            segment.endTimeSeconds > self.lastAssignedBoundarySeconds
        }
        logDiagnostic("  Active segments in window: \(windowSegments.count)")
        for segment in windowSegments {
            logDiagnostic("    Segment: Speaker \(segment.speakerIndex), \(segment.startTimeSeconds)s-\(segment.endTimeSeconds)s (final=\(segment.isFinal))")
        }

        let attribution = DominantSpeakerMatcher.attributeNextTurn(
            segments: currentSnapshot.segments,
            previousBoundarySeconds: lastAssignedBoundarySeconds,
            audioDurationSeconds: currentSnapshot.totalAudioSeconds,
            eouDebounceMs: eouDebounceMs,
            speakerLabel: speakerLabel(for:)
        )

        logDiagnostic("  Result: \(attribution.speakerLabel) (index: \(attribution.speakerIndex.map(String.init) ?? "nil"), confidence: \(attribution.confidence))")

        lastAssignedBoundarySeconds = attribution.estimatedEndTimeSeconds
        return attribution
    }

    func speakerLabel(for speakerIndex: Int) -> String {
        if let existingLabel = speakerLabelsByIndex[speakerIndex] {
            return existingLabel
        }

        let label = defaultSpeakerLabel(for: speakerLabelsByIndex.count)

        speakerLabelsByIndex[speakerIndex] = label
        return label
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
        audioProvider: MicrophoneAudioProvider,
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

        let audioEngine = audioProvider.engine
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

    nonisolated static func makeHandler(
        asrManager: StreamingEouAsrManager,
        diarizationEngine: LiveDiarizationEngine?,
        preprocessor: AudioPreprocessor? = nil
    ) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in
            // Apply preprocessing if available
            let processedBuffer: AVAudioPCMBuffer
            if let preprocessor {
                processedBuffer = preprocessor.processCopy(buffer)
            } else {
                processedBuffer = buffer
            }

            guard let bufferBox = processedBuffer.deepCopy().map(SendablePCMBufferBox.init) else { return }

            Task {
                do {
                    if let diarizationEngine {
                        try await diarizationEngine.ingest(bufferBox.buffer)
                    }
                    _ = try await asrManager.process(audioBuffer: bufferBox.buffer)
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

private func defaultSpeakerLabel(for speakerIndex: Int) -> String {
    switch speakerIndex {
    case 0:
        return "Speaker A"
    case 1:
        return "Speaker B"
    case 2:
        return "Speaker C"
    case 3:
        return "Speaker D"
    default:
        return "Speaker \(speakerIndex + 1)"
    }
}
