import Foundation
import InterviewPartnerDomain

public struct ReplayExpectedTurn: Codable, Hashable, Sendable {
    public let text: String
    public let speakerLabel: String
    public let startSeconds: Double
    public let endSeconds: Double

    public init(text: String, speakerLabel: String, startSeconds: Double, endSeconds: Double) {
        self.text = text
        self.speakerLabel = speakerLabel
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    enum CodingKeys: String, CodingKey {
        case text
        case speakerLabel = "speaker_label"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }
}

public struct ReplayFixture: Codable, Sendable {
    public let fixtureID: String
    public let fixtureSet: String
    public let description: String
    public let audioFileName: String?
    public let frames: [ReplayFrame]
    public let expectedTurns: [ReplayExpectedTurn]
    public let offlineDiarizationSegments: [DiarizedSegment]
    public let offlineRuntimeSeconds: Double

    public init(
        fixtureID: String,
        fixtureSet: String,
        description: String,
        audioFileName: String?,
        frames: [ReplayFrame],
        expectedTurns: [ReplayExpectedTurn],
        offlineDiarizationSegments: [DiarizedSegment],
        offlineRuntimeSeconds: Double
    ) {
        self.fixtureID = fixtureID
        self.fixtureSet = fixtureSet
        self.description = description
        self.audioFileName = audioFileName
        self.frames = frames
        self.expectedTurns = expectedTurns
        self.offlineDiarizationSegments = offlineDiarizationSegments
        self.offlineRuntimeSeconds = offlineRuntimeSeconds
    }

    enum CodingKeys: String, CodingKey {
        case fixtureID = "fixture_id"
        case fixtureSet = "fixture_set"
        case description
        case audioFileName = "audio_file_name"
        case frames
        case expectedTurns = "expected_turns"
        case offlineDiarizationSegments = "offline_diarization_segments"
        case offlineRuntimeSeconds = "offline_runtime_seconds"
    }
}

public struct FixtureBenchmarkMetrics: Codable, Hashable, Sendable {
    public let expectedTurnCount: Int
    public let actualLiveTurnCount: Int
    public let actualFinalTurnCount: Int
    public let turnBoundaryMAEMs: Double
    public let lateFinalizationP95Ms: Double
    public let splitMergeErrorCount: Int
    public let expectedTurnRecall: Double
    public let actualTurnPrecision: Double
    public let missingExpectedTurnCount: Int
    public let extraActualTurnCount: Int
    public let sessionCoverageRatio: Double
    public let liveSpeakerAccuracy: Double
    public let finalSpeakerAccuracy: Double
    public let expectedSpeakerCount: Int
    public let actualLiveSpeakerCount: Int
    public let actualFinalSpeakerCount: Int
    public let liveSpeakerCoverageRecall: Double
    public let finalSpeakerCoverageRecall: Double
    public let liveSpeakerCountError: Int
    public let finalSpeakerCountError: Int
    public let unclearRate: Double
    public let offlineRuntimeRTF: Double
    public let missingSpeechEndCount: Int

    public init(
        expectedTurnCount: Int,
        actualLiveTurnCount: Int,
        actualFinalTurnCount: Int,
        turnBoundaryMAEMs: Double,
        lateFinalizationP95Ms: Double,
        splitMergeErrorCount: Int,
        expectedTurnRecall: Double,
        actualTurnPrecision: Double,
        missingExpectedTurnCount: Int,
        extraActualTurnCount: Int,
        sessionCoverageRatio: Double,
        liveSpeakerAccuracy: Double,
        finalSpeakerAccuracy: Double,
        expectedSpeakerCount: Int,
        actualLiveSpeakerCount: Int,
        actualFinalSpeakerCount: Int,
        liveSpeakerCoverageRecall: Double,
        finalSpeakerCoverageRecall: Double,
        liveSpeakerCountError: Int,
        finalSpeakerCountError: Int,
        unclearRate: Double,
        offlineRuntimeRTF: Double,
        missingSpeechEndCount: Int
    ) {
        self.expectedTurnCount = expectedTurnCount
        self.actualLiveTurnCount = actualLiveTurnCount
        self.actualFinalTurnCount = actualFinalTurnCount
        self.turnBoundaryMAEMs = turnBoundaryMAEMs
        self.lateFinalizationP95Ms = lateFinalizationP95Ms
        self.splitMergeErrorCount = splitMergeErrorCount
        self.expectedTurnRecall = expectedTurnRecall
        self.actualTurnPrecision = actualTurnPrecision
        self.missingExpectedTurnCount = missingExpectedTurnCount
        self.extraActualTurnCount = extraActualTurnCount
        self.sessionCoverageRatio = sessionCoverageRatio
        self.liveSpeakerAccuracy = liveSpeakerAccuracy
        self.finalSpeakerAccuracy = finalSpeakerAccuracy
        self.expectedSpeakerCount = expectedSpeakerCount
        self.actualLiveSpeakerCount = actualLiveSpeakerCount
        self.actualFinalSpeakerCount = actualFinalSpeakerCount
        self.liveSpeakerCoverageRecall = liveSpeakerCoverageRecall
        self.finalSpeakerCoverageRecall = finalSpeakerCoverageRecall
        self.liveSpeakerCountError = liveSpeakerCountError
        self.finalSpeakerCountError = finalSpeakerCountError
        self.unclearRate = unclearRate
        self.offlineRuntimeRTF = offlineRuntimeRTF
        self.missingSpeechEndCount = missingSpeechEndCount
    }

    enum CodingKeys: String, CodingKey {
        case expectedTurnCount = "expected_turn_count"
        case actualLiveTurnCount = "actual_live_turn_count"
        case actualFinalTurnCount = "actual_final_turn_count"
        case turnBoundaryMAEMs = "turn_boundary_mae_ms"
        case lateFinalizationP95Ms = "late_finalization_p95_ms"
        case splitMergeErrorCount = "split_merge_error_count"
        case expectedTurnRecall = "expected_turn_recall"
        case actualTurnPrecision = "actual_turn_precision"
        case missingExpectedTurnCount = "missing_expected_turn_count"
        case extraActualTurnCount = "extra_actual_turn_count"
        case sessionCoverageRatio = "session_coverage_ratio"
        case liveSpeakerAccuracy = "live_speaker_accuracy"
        case finalSpeakerAccuracy = "final_speaker_accuracy"
        case expectedSpeakerCount = "expected_speaker_count"
        case actualLiveSpeakerCount = "actual_live_speaker_count"
        case actualFinalSpeakerCount = "actual_final_speaker_count"
        case liveSpeakerCoverageRecall = "live_speaker_coverage_recall"
        case finalSpeakerCoverageRecall = "final_speaker_coverage_recall"
        case liveSpeakerCountError = "live_speaker_count_error"
        case finalSpeakerCountError = "final_speaker_count_error"
        case unclearRate = "unclear_rate"
        case offlineRuntimeRTF = "offline_runtime_rtf"
        case missingSpeechEndCount = "missing_speech_end_count"
    }

    func value(named metricName: String) -> Double? {
        switch metricName {
        case "expected_turn_count":
            return Double(expectedTurnCount)
        case "actual_live_turn_count":
            return Double(actualLiveTurnCount)
        case "actual_final_turn_count":
            return Double(actualFinalTurnCount)
        case "turn_boundary_mae_ms":
            return turnBoundaryMAEMs
        case "late_finalization_p95_ms":
            return lateFinalizationP95Ms
        case "split_merge_error_count":
            return Double(splitMergeErrorCount)
        case "expected_turn_recall":
            return expectedTurnRecall
        case "actual_turn_precision":
            return actualTurnPrecision
        case "missing_expected_turn_count":
            return Double(missingExpectedTurnCount)
        case "extra_actual_turn_count":
            return Double(extraActualTurnCount)
        case "session_coverage_ratio":
            return sessionCoverageRatio
        case "live_speaker_accuracy":
            return liveSpeakerAccuracy
        case "final_speaker_accuracy":
            return finalSpeakerAccuracy
        case "expected_speaker_count":
            return Double(expectedSpeakerCount)
        case "actual_live_speaker_count":
            return Double(actualLiveSpeakerCount)
        case "actual_final_speaker_count":
            return Double(actualFinalSpeakerCount)
        case "live_speaker_coverage_recall":
            return liveSpeakerCoverageRecall
        case "final_speaker_coverage_recall":
            return finalSpeakerCoverageRecall
        case "live_speaker_count_error":
            return Double(liveSpeakerCountError)
        case "final_speaker_count_error":
            return Double(finalSpeakerCountError)
        case "unclear_rate":
            return unclearRate
        case "offline_runtime_rtf":
            return offlineRuntimeRTF
        case "missing_speech_end_count":
            return Double(missingSpeechEndCount)
        default:
            return nil
        }
    }
}

public struct FixtureBenchmarkReport: Codable, Hashable, Sendable {
    public let fixtureID: String
    public let description: String
    public let metrics: FixtureBenchmarkMetrics
    public let notes: [String]

    public init(
        fixtureID: String,
        description: String,
        metrics: FixtureBenchmarkMetrics,
        notes: [String]
    ) {
        self.fixtureID = fixtureID
        self.description = description
        self.metrics = metrics
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case fixtureID = "fixture_id"
        case description
        case metrics
        case notes
    }
}

public struct TranscriptionBenchmarkReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let fixtureSet: String
    public let variant: String
    public let fixtures: [FixtureBenchmarkReport]

    public init(generatedAt: Date, fixtureSet: String, variant: String, fixtures: [FixtureBenchmarkReport]) {
        self.generatedAt = generatedAt
        self.fixtureSet = fixtureSet
        self.variant = variant
        self.fixtures = fixtures
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case fixtureSet = "fixture_set"
        case variant
        case fixtures
    }
}

struct BenchmarkTurn: Hashable, Sendable {
    let turn: TranscriptTurn
    let finalizedAtSeconds: Double
}

public struct ReplayBenchmarkVariant: Sendable {
    public let name: String
    public let useVadBoundaries: Bool
    public let useOfflineFinalSpeakerLabels: Bool
    public let tuning: DiarizationTuning

    public init(
        name: String,
        useVadBoundaries: Bool,
        useOfflineFinalSpeakerLabels: Bool,
        tuning: DiarizationTuning
    ) {
        self.name = name
        self.useVadBoundaries = useVadBoundaries
        self.useOfflineFinalSpeakerLabels = useOfflineFinalSpeakerLabels
        self.tuning = tuning
    }

    public static let phase1Baseline = ReplayBenchmarkVariant(
        name: "phase1_baseline",
        useVadBoundaries: false,
        useOfflineFinalSpeakerLabels: false,
        tuning: .productionDefault
    )

    public static let productionCurrent = ReplayBenchmarkVariant(
        name: "production_current",
        useVadBoundaries: true,
        useOfflineFinalSpeakerLabels: true,
        tuning: .productionDefault
    )

    public static let pinnedTuned = ReplayBenchmarkVariant(
        name: "pinned_tuned",
        useVadBoundaries: true,
        useOfflineFinalSpeakerLabels: true,
        tuning: .benchmarkPinnedTuned
    )
}

public enum TranscriptionBenchmarkRunner {
    public static func loadFixtures(
        at fixturesRoot: URL,
        fixtureSet: String
    ) throws -> [ReplayFixture] {
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixturesRoot,
            includingPropertiesForKeys: nil
        )
        let decoder = JSONDecoder()

        return try fixtureURLs
            .filter { $0.pathExtension == "json" }
            .map { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(ReplayFixture.self, from: data)
            }
            .filter { $0.fixtureSet == fixtureSet }
            .sorted { $0.fixtureID < $1.fixtureID }
    }

    public static func run(
        fixtures: [ReplayFixture],
        variant: ReplayBenchmarkVariant
    ) -> TranscriptionBenchmarkReport {
        let fixtureReports = fixtures.map { fixture in
            evaluateFixture(fixture, variant: variant)
        }

        return TranscriptionBenchmarkReport(
            generatedAt: Date(),
            fixtureSet: fixtures.first?.fixtureSet ?? "unknown",
            variant: variant.name,
            fixtures: fixtureReports
        )
    }

    private static func evaluateFixture(
        _ fixture: ReplayFixture,
        variant: ReplayBenchmarkVariant
    ) -> FixtureBenchmarkReport {
        var deltaAccumulator = TranscriptDeltaAccumulator()
        var vadTracker = VadBoundaryTracker()
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let syntheticSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

        var currentTranscript = ""
        var liveTurns: [BenchmarkTurn] = []
        var lastTurnEndSeconds: Double?
        var missingSpeechEndCount = 0
        var gapNotes: [String] = []

        for frame in fixture.frames.sorted(by: { $0.elapsedSeconds < $1.elapsedSeconds }) {
            if let vadEvent = frame.vadEvent {
                vadTracker.ingest(event: vadEvent)
            }
            if let cumulativeTranscript = frame.cumulativeTranscript {
                currentTranscript = cumulativeTranscript
            }

            guard frame.eouDetected else { continue }

            let deltaText = deltaAccumulator.commit(currentTranscript)
            let trimmedText = deltaText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }

            let window: UtteranceWindow
            let missedSpeechEnd: Bool
            if variant.useVadBoundaries {
                let result = vadTracker.consumeBestWindow(
                    audioDurationSeconds: frame.elapsedSeconds,
                    previousBoundarySeconds: lastTurnEndSeconds ?? 0,
                    eouDebounceMs: 640
                )
                window = result.window
                missedSpeechEnd = result.missedSpeechEnd
            } else {
                window = VadBoundaryTracker.fallbackWindow(
                    previousBoundarySeconds: lastTurnEndSeconds ?? 0,
                    audioDurationSeconds: frame.elapsedSeconds,
                    eouDebounceMs: 640
                )
                missedSpeechEnd = false
            }

            if missedSpeechEnd {
                missingSpeechEndCount += 1
            }

            let assembled = LiveTurnAssembler.assembleTurn(
                sessionID: syntheticSessionID,
                startedAt: startedAt,
                previousTurnEndTimeSeconds: lastTurnEndSeconds,
                text: trimmedText,
                diarizationAvailable: true,
                window: window,
                diarizationSegments: frame.diarizationSegments,
                gapThresholdSeconds: 10,
                tuning: variant.tuning
            )

            if let gap = assembled.gap {
                gapNotes.append(
                    "Gap \(gap.startTimestamp.timeIntervalSince(startedAt))-\(gap.endTimestamp.timeIntervalSince(startedAt))"
                )
            }

            liveTurns.append(BenchmarkTurn(turn: assembled.turn, finalizedAtSeconds: frame.elapsedSeconds))
            lastTurnEndSeconds = assembled.turn.endTimeSeconds
        }

        let finalizedTurns: [TranscriptTurn]
        let offlineRuntimeRTF: Double
        if variant.useOfflineFinalSpeakerLabels {
            let finalSnapshot = DiarizationSnapshot(
                totalAudioSeconds: fixture.frames.last?.elapsedSeconds ?? 0,
                segments: fixture.offlineDiarizationSegments,
                attributedSpeakerCount: Set(fixture.offlineDiarizationSegments.map(\.speakerIndex)).count
            )
            finalizedTurns = LiveTurnAssembler.reconcileTurns(
                snapshot: finalSnapshot,
                turns: liveTurns.map(\.turn),
                tuning: variant.tuning
            )
            let duration = max(fixture.frames.last?.elapsedSeconds ?? 0, 0.001)
            offlineRuntimeRTF = fixture.offlineRuntimeSeconds / duration
        } else {
            finalizedTurns = LiveTurnAssembler.reconcileTurns(
                snapshot: DiarizationSnapshot(
                    totalAudioSeconds: fixture.frames.last?.elapsedSeconds ?? 0,
                    segments: fixture.frames.last?.diarizationSegments ?? [],
                    attributedSpeakerCount: Set((fixture.frames.last?.diarizationSegments ?? []).map(\.speakerIndex)).count
                ),
                turns: liveTurns.map(\.turn),
                tuning: variant.tuning
            )
            offlineRuntimeRTF = 0
        }

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
        if metrics.splitMergeErrorCount > 0 {
            notes.append("Turn split/merge mismatch detected.")
        }
        if metrics.expectedTurnRecall < 1 {
            notes.append(
                "Expected turn recall fell to \(metrics.actualLiveTurnCount)/\(metrics.expectedTurnCount)."
            )
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
}
