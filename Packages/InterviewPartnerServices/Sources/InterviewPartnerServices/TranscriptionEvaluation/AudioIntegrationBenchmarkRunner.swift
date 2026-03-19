import AVFoundation
import FluidAudio
import Foundation
import InterviewPartnerDomain

public enum AudioIntegrationBenchmarkRunner {
    public static func run(
        fixtures: [ReplayFixture],
        fixturesRoot: URL,
        variant: ReplayBenchmarkVariant
    ) async throws -> TranscriptionBenchmarkReport {
        let fixtureReports = try await fixtures.asyncMap { fixture in
            try await evaluateFixture(fixture, fixturesRoot: fixturesRoot, variant: variant)
        }

        return TranscriptionBenchmarkReport(
            generatedAt: Date(),
            fixtureSet: fixtures.first?.fixtureSet ?? "unknown",
            variant: "\(variant.name)_audio_integration",
            fixtures: fixtureReports
        )
    }

    private static func evaluateFixture(
        _ fixture: ReplayFixture,
        fixturesRoot: URL,
        variant: ReplayBenchmarkVariant
    ) async throws -> FixtureBenchmarkReport {
        guard let audioFileName = fixture.audioFileName else {
            throw AudioIntegrationBenchmarkError.missingAudioFileName(fixtureID: fixture.fixtureID)
        }

        let audioURL = fixturesRoot.appendingPathComponent(audioFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioIntegrationBenchmarkError.audioFileNotFound(audioURL.path)
        }

        let asrManager = StreamingEouAsrManager(
            chunkSize: .ms160,
            eouDebounceMs: 640
        )
        let diarizationEngine = LiveDiarizationEngine(tuning: variant.tuning)
        let vadEngine = StreamingVadEngine()
        let offlineReconciler = OfflineDiarizationReconciler(tuning: variant.tuning)
        let state = AudioIntegrationBenchmarkState(tuning: variant.tuning, useVadBoundaries: variant.useVadBoundaries)
        let callbackTracker = AudioTapWorkTracker()

        let modelDirectory = defaultModelsDirectory(for: .ms160)
        try await downloadModelsIfNeeded(to: modelDirectory, chunkSize: .ms160)
        try await asrManager.loadModels(modelDir: modelDirectory)
        try await diarizationEngine.prepareIfNeeded()
        try await vadEngine.prepareIfNeeded()
        await asrManager.reset()
        await diarizationEngine.reset()
        await vadEngine.reset()

        await asrManager.setPartialCallback { _ in }
        await asrManager.setEouCallback { transcript in
            callbackTracker.begin()
            Task {
                defer { callbackTracker.end() }
                let snapshot = await diarizationEngine.currentSnapshot()
                let audioDurationSeconds = await state.audioDurationSeconds()
                await state.handleEou(
                    transcript: transcript,
                    diarizationSegments: snapshot.segments,
                    audioDurationSeconds: audioDurationSeconds
                )
            }
        }

        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let bufferSize: AVAudioFrameCount = 2048
        var processedFrames: AVAudioFramePosition = 0

        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
                throw AudioIntegrationBenchmarkError.bufferAllocationFailed
            }

            try audioFile.read(into: buffer, frameCount: bufferSize)
            if buffer.frameLength == 0 {
                break
            }

            processedFrames += AVAudioFramePosition(buffer.frameLength)
            let elapsedSeconds = Double(processedFrames) / format.sampleRate
            await state.updateAudioDuration(elapsedSeconds)

            try await processAsrBuffer(buffer, with: asrManager)
            try await processDiarizationBuffer(buffer, with: diarizationEngine)

            if variant.useVadBoundaries {
                let events = try await processVadBuffer(buffer, with: vadEngine)
                for event in events {
                    await state.ingestVadEvent(event)
                }
            }
        }

        let finalTranscript = try await asrManager.finish()
        let liveSnapshot = await diarizationEngine.currentSnapshot()
        await state.handleEou(
            transcript: finalTranscript,
            diarizationSegments: liveSnapshot.segments,
            audioDurationSeconds: await state.audioDurationSeconds()
        )
        await callbackTracker.waitUntilIdle()

        let liveTurns = await state.recordedLiveTurns()
        let finalSnapshot = await diarizationEngine.finalizeAndSnapshot()

        let finalizedTurns: [TranscriptTurn]
        let offlineRuntimeRTF: Double
        if variant.useOfflineFinalSpeakerLabels {
            let offlineStartedAt = Date()
            let offlineResult = await offlineReconciler.reconcile(
                turns: liveTurns.map { $0.turn },
                audioURL: audioURL
            )
            let elapsed = Date().timeIntervalSince(offlineStartedAt)
            let audioDuration = max(await state.audioDurationSeconds(), 0.001)
            offlineRuntimeRTF = elapsed / audioDuration
            finalizedTurns = offlineResult.usedOfflineDiarization
                ? offlineResult.turns
                : LiveTurnAssembler.reconcileTurns(
                    snapshot: finalSnapshot,
                    turns: liveTurns.map { $0.turn },
                    tuning: variant.tuning
                )
        } else {
            finalizedTurns = LiveTurnAssembler.reconcileTurns(
                snapshot: finalSnapshot,
                turns: liveTurns.map { $0.turn },
                tuning: variant.tuning
            )
            offlineRuntimeRTF = 0
        }

        return buildReport(
            fixture: fixture,
            liveTurns: liveTurns,
            finalizedTurns: finalizedTurns,
            offlineRuntimeRTF: offlineRuntimeRTF,
            missingSpeechEndCount: await state.recordedMissingSpeechEndCount(),
            gapNotes: await state.recordedGapNotes()
        )
    }

    private static func buildReport(
        fixture: ReplayFixture,
        liveTurns: [BenchmarkTurn],
        finalizedTurns: [TranscriptTurn],
        offlineRuntimeRTF: Double,
        missingSpeechEndCount: Int,
        gapNotes: [String]
    ) -> FixtureBenchmarkReport {
        let metrics = FixtureBenchmarkMetrics(
            expectedTurnCount: fixture.expectedTurns.count,
            actualLiveTurnCount: liveTurns.count,
            actualFinalTurnCount: finalizedTurns.count,
            turnBoundaryMAEMs: BoundaryMetrics.meanAbsoluteBoundaryErrorMs(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            lateFinalizationP95Ms: BoundaryMetrics.lateFinalizationP95Ms(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            splitMergeErrorCount: BoundaryMetrics.splitMergeErrorCount(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            expectedTurnRecall: BoundaryMetrics.expectedTurnRecall(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            actualTurnPrecision: BoundaryMetrics.actualTurnPrecision(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            missingExpectedTurnCount: BoundaryMetrics.missingExpectedTurnCount(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            extraActualTurnCount: BoundaryMetrics.extraActualTurnCount(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            sessionCoverageRatio: BoundaryMetrics.sessionCoverageRatio(
                actual: liveTurns,
                expected: fixture.expectedTurns
            ),
            liveSpeakerAccuracy: SpeakerMetrics.accuracy(
                actual: liveTurns,
                expected: fixture.expectedTurns,
                label: { $0.turn.speakerLabel }
            ),
            finalSpeakerAccuracy: SpeakerMetrics.accuracy(
                actual: finalizedTurns,
                expected: fixture.expectedTurns,
                label: \.speakerLabel
            ),
            expectedSpeakerCount: SpeakerMetrics.expectedSpeakerCount(expected: fixture.expectedTurns),
            actualLiveSpeakerCount: SpeakerMetrics.distinctSpeakerCount(
                actual: liveTurns,
                label: { $0.turn.speakerLabel }
            ),
            actualFinalSpeakerCount: SpeakerMetrics.distinctSpeakerCount(
                actual: finalizedTurns,
                label: \.speakerLabel
            ),
            liveSpeakerCoverageRecall: SpeakerMetrics.speakerCoverageRecall(
                actual: liveTurns,
                expected: fixture.expectedTurns,
                label: { $0.turn.speakerLabel }
            ),
            finalSpeakerCoverageRecall: SpeakerMetrics.speakerCoverageRecall(
                actual: finalizedTurns,
                expected: fixture.expectedTurns,
                label: \.speakerLabel
            ),
            liveSpeakerCountError: SpeakerMetrics.speakerCountError(
                actual: liveTurns,
                expected: fixture.expectedTurns,
                label: { $0.turn.speakerLabel }
            ),
            finalSpeakerCountError: SpeakerMetrics.speakerCountError(
                actual: finalizedTurns,
                expected: fixture.expectedTurns,
                label: \.speakerLabel
            ),
            unclearRate: SpeakerMetrics.unclearRate(
                actual: finalizedTurns,
                label: \.speakerLabel
            ),
            offlineRuntimeRTF: offlineRuntimeRTF,
            missingSpeechEndCount: missingSpeechEndCount
        )

        var notes = gapNotes
        notes.append("Audio-driven integration benchmark.")
        if metrics.splitMergeErrorCount > 0 {
            notes.append("Turn split/merge mismatch detected.")
        }
        if metrics.expectedTurnRecall < 1 {
            notes.append("Expected turn recall fell to \(metrics.actualLiveTurnCount)/\(metrics.expectedTurnCount).")
        }
        if metrics.actualTurnPrecision < 1 {
            notes.append("Extra or mismatched live turns detected.")
        }
        if metrics.sessionCoverageRatio < 1 {
            notes.append(
                "Session coverage only reached \(String(format: "%.2f", metrics.sessionCoverageRatio * 100))% of the expected timeline."
            )
        }
        if metrics.liveSpeakerAccuracy < 1 {
            notes.append("Live speaker label mismatch detected.")
        }
        if metrics.finalSpeakerAccuracy < 1 {
            notes.append("Final speaker label mismatch detected.")
        }
        if metrics.liveSpeakerCountError > 0 {
            notes.append("Live speaker cardinality mismatch detected.")
        }
        if metrics.finalSpeakerCountError > 0 {
            notes.append("Final speaker cardinality mismatch detected.")
        }

        return FixtureBenchmarkReport(
            fixtureID: fixture.fixtureID,
            description: fixture.description,
            metrics: metrics,
            notes: notes
        )
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

    private static func processAsrBuffer(
        _ buffer: AVAudioPCMBuffer,
        with asrManager: StreamingEouAsrManager
    ) async throws {
        guard let copiedBuffer = buffer.deepCopyForBenchmark() else {
            throw AudioIntegrationBenchmarkError.bufferAllocationFailed
        }
        let bufferBox = SendableBenchmarkPCMBufferBox(copiedBuffer)
        _ = try await asrManager.process(audioBuffer: bufferBox.buffer)
    }

    private static func processDiarizationBuffer(
        _ buffer: AVAudioPCMBuffer,
        with diarizationEngine: LiveDiarizationEngine
    ) async throws {
        guard let copiedBuffer = buffer.deepCopyForBenchmark() else {
            throw AudioIntegrationBenchmarkError.bufferAllocationFailed
        }
        let bufferBox = SendableBenchmarkPCMBufferBox(copiedBuffer)
        try await diarizationEngine.ingest(bufferBox.buffer)
    }

    private static func processVadBuffer(
        _ buffer: AVAudioPCMBuffer,
        with vadEngine: StreamingVadEngine
    ) async throws -> [VadBoundaryEvent] {
        guard let copiedBuffer = buffer.deepCopyForBenchmark() else {
            throw AudioIntegrationBenchmarkError.bufferAllocationFailed
        }
        let bufferBox = SendableBenchmarkPCMBufferBox(copiedBuffer)
        return try await vadEngine.ingest(bufferBox.buffer)
    }
}

private actor AudioIntegrationBenchmarkState {
    private let tuning: DiarizationTuning
    private let useVadBoundaries: Bool
    private let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000099") ?? UUID()

    private var deltaAccumulator = TranscriptDeltaAccumulator()
    private var vadTracker = VadBoundaryTracker()
    private var recordedLiveTurnsStorage: [BenchmarkTurn] = []
    private var lastTurnEndSeconds: Double?
    private var currentAudioDurationSeconds = 0.0
    private var recordedMissingSpeechEndCountStorage = 0
    private var recordedGapNotesStorage: [String] = []

    init(tuning: DiarizationTuning, useVadBoundaries: Bool) {
        self.tuning = tuning
        self.useVadBoundaries = useVadBoundaries
    }

    func updateAudioDuration(_ seconds: Double) {
        currentAudioDurationSeconds = seconds
    }

    func audioDurationSeconds() -> Double {
        currentAudioDurationSeconds
    }

    func ingestVadEvent(_ event: VadBoundaryEvent) {
        vadTracker.ingest(event: event)
    }

    func handleEou(
        transcript: String,
        diarizationSegments: [DiarizedSegment],
        audioDurationSeconds: Double
    ) {
        let newText = deltaAccumulator.commit(transcript)
        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let window: UtteranceWindow
        if useVadBoundaries {
            let result = vadTracker.consumeBestWindow(
                audioDurationSeconds: audioDurationSeconds,
                previousBoundarySeconds: lastTurnEndSeconds ?? 0,
                eouDebounceMs: 640
            )
            window = result.window
            if result.missedSpeechEnd {
                recordedMissingSpeechEndCountStorage += 1
            }
        } else {
            window = VadBoundaryTracker.fallbackWindow(
                previousBoundarySeconds: lastTurnEndSeconds ?? 0,
                audioDurationSeconds: audioDurationSeconds,
                eouDebounceMs: 640
            )
        }

        let assembly = LiveTurnAssembler.assembleTurn(
            sessionID: sessionID,
            startedAt: startedAt,
            previousTurnEndTimeSeconds: lastTurnEndSeconds,
            text: trimmedText,
            diarizationAvailable: true,
            window: window,
            diarizationSegments: diarizationSegments,
            gapThresholdSeconds: 10,
            tuning: tuning
        )

        if let gap = assembly.gap {
            recordedGapNotesStorage.append(
                "Gap \(gap.startTimestamp.timeIntervalSince(startedAt))-\(gap.endTimestamp.timeIntervalSince(startedAt))"
            )
        }

        recordedLiveTurnsStorage.append(BenchmarkTurn(turn: assembly.turn, finalizedAtSeconds: audioDurationSeconds))
        lastTurnEndSeconds = assembly.turn.endTimeSeconds
    }

    func recordedLiveTurns() -> [BenchmarkTurn] {
        recordedLiveTurnsStorage
    }

    func recordedMissingSpeechEndCount() -> Int {
        recordedMissingSpeechEndCountStorage
    }

    func recordedGapNotes() -> [String] {
        recordedGapNotesStorage
    }
}

private enum AudioIntegrationBenchmarkError: LocalizedError {
    case missingAudioFileName(fixtureID: String)
    case audioFileNotFound(String)
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .missingAudioFileName(let fixtureID):
            return "Audio integration benchmark fixture \(fixtureID) is missing an audio_file_name."
        case .audioFileNotFound(let path):
            return "Audio integration benchmark could not find fixture audio at \(path)."
        case .bufferAllocationFailed:
            return "Unable to allocate an audio buffer for integration benchmarking."
        }
    }
}

private extension Array {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            let value = try await transform(element)
            results.append(value)
        }
        return results
    }
}

private extension AVAudioPCMBuffer {
    func deepCopyForBenchmark() -> AVAudioPCMBuffer? {
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

private final class SendableBenchmarkPCMBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
