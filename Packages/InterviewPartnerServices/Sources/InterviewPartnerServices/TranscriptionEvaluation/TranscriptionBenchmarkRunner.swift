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
    public let turnBoundaryMAEMs: Double
    public let lateFinalizationP95Ms: Double
    public let splitMergeErrorCount: Int
    public let liveSpeakerAccuracy: Double
    public let finalSpeakerAccuracy: Double
    public let unclearRate: Double
    public let offlineRuntimeRTF: Double
    public let missingSpeechEndCount: Int

    public init(
        turnBoundaryMAEMs: Double,
        lateFinalizationP95Ms: Double,
        splitMergeErrorCount: Int,
        liveSpeakerAccuracy: Double,
        finalSpeakerAccuracy: Double,
        unclearRate: Double,
        offlineRuntimeRTF: Double,
        missingSpeechEndCount: Int
    ) {
        self.turnBoundaryMAEMs = turnBoundaryMAEMs
        self.lateFinalizationP95Ms = lateFinalizationP95Ms
        self.splitMergeErrorCount = splitMergeErrorCount
        self.liveSpeakerAccuracy = liveSpeakerAccuracy
        self.finalSpeakerAccuracy = finalSpeakerAccuracy
        self.unclearRate = unclearRate
        self.offlineRuntimeRTF = offlineRuntimeRTF
        self.missingSpeechEndCount = missingSpeechEndCount
    }

    enum CodingKeys: String, CodingKey {
        case turnBoundaryMAEMs = "turn_boundary_mae_ms"
        case lateFinalizationP95Ms = "late_finalization_p95_ms"
        case splitMergeErrorCount = "split_merge_error_count"
        case liveSpeakerAccuracy = "live_speaker_accuracy"
        case finalSpeakerAccuracy = "final_speaker_accuracy"
        case unclearRate = "unclear_rate"
        case offlineRuntimeRTF = "offline_runtime_rtf"
        case missingSpeechEndCount = "missing_speech_end_count"
    }

    func value(named metricName: String) -> Double? {
        switch metricName {
        case "turn_boundary_mae_ms":
            return turnBoundaryMAEMs
        case "late_finalization_p95_ms":
            return lateFinalizationP95Ms
        case "split_merge_error_count":
            return Double(splitMergeErrorCount)
        case "live_speaker_accuracy":
            return liveSpeakerAccuracy
        case "final_speaker_accuracy":
            return finalSpeakerAccuracy
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
        if metrics.liveSpeakerAccuracy < 1 {
            notes.append("Live speaker label mismatch detected.")
        }
        if metrics.finalSpeakerAccuracy < 1 {
            notes.append("Final speaker label mismatch detected.")
        }

        return FixtureBenchmarkReport(
            fixtureID: fixture.fixtureID,
            description: fixture.description,
            metrics: metrics,
            notes: notes
        )
    }
}
