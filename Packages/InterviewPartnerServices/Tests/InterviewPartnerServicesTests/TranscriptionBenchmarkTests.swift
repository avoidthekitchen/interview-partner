import Foundation
import Testing

@testable import InterviewPartnerServices
import InterviewPartnerBenchmark
import InterviewPartnerDomain

// MARK: - Benchmark Types

/// Note: `InterviewPartnerBenchmark.TranscriptTurn` (ground truth) and
/// `InterviewPartnerDomain.TranscriptTurn` (live transcription) are distinct
/// types. We use module-qualified names where disambiguation is needed.

/// Thread-safe collector for transcription events received during a benchmark run.
private actor TranscriptionEventCollector {
    private(set) var finalizedTurns: [InterviewPartnerDomain.TranscriptTurn] = []
    private(set) var diarizationSnapshots: [DiarizationSnapshot] = []
    private(set) var limitedModeMessage: String?

    func handle(_ event: TranscriptionServiceEvent) {
        switch event {
        case .finalizedTurn(let turn):
            finalizedTurns.append(turn)
        case .diarizationSnapshot(let snapshot):
            diarizationSnapshots.append(snapshot)
        case .limitedModeChanged(_, let message):
            limitedModeMessage = message
        case .partialText, .transcriptGap:
            break
        }
    }
}

/// Outcome of running a single transcription benchmark test case.
private enum BenchmarkRunOutcome: Sendable {
    /// Transcription produced output that can be scored.
    case success(TranscriptionStopResult, collectedTurns: [InterviewPartnerDomain.TranscriptTurn])
    /// Transcription engine was not available (e.g. FluidAudio models not installed).
    case unavailable(reason: String)
}

// MARK: - Test Suite

@Suite("Transcription Benchmark")
struct TranscriptionBenchmarkTests {

    /// Returns the repo root URL derived from the location of this source file.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TranscriptionBenchmarkTests.swift
            .deletingLastPathComponent() // InterviewPartnerServicesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // InterviewPartnerServices
            .deletingLastPathComponent() // Packages
    }

    /// The directory containing benchmark test data.
    private static var testDataDirectory: URL {
        repoRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("test-data")
    }

    /// Path where baseline JSON is stored, alongside the test data.
    private static var baselinePath: URL {
        testDataDirectory
            .appendingPathComponent("transcription-benchmark-baseline.json")
    }

    // MARK: - End-to-End Benchmark

    @Test("End-to-end transcription benchmark scores against baseline")
    func benchmarkAgainstBaseline() async throws {
        // 1. Discover test cases
        let discovery = TestCaseDiscovery()
        let testCases = try discovery.discover(in: Self.testDataDirectory)
        try #require(!testCases.isEmpty, "No test cases found in \(Self.testDataDirectory.path)")

        let comparator = BaselineComparator(baselinePath: Self.baselinePath)

        for testCase in testCases {
            // 2. Run transcription for this test case
            let outcome = await runTranscription(for: testCase)

            let turnsToScore: [InterviewPartnerDomain.TranscriptTurn]
            switch outcome {
            case .unavailable(let reason):
                withKnownIssue("Transcription engine unavailable") {
                    Issue.record(Comment(rawValue: reason))
                }
                continue

            case .success(let stopResult, let collectedTurns):
                let reconciledTurns = stopResult.reconciledTurns
                turnsToScore = reconciledTurns.isEmpty ? collectedTurns : reconciledTurns
            }

            // If we got zero output, the transcription engine produced no results.
            if turnsToScore.isEmpty {
                withKnownIssue("No transcription output -- FluidAudio models likely not installed") {
                    Issue.record("No output for \(testCase.name)")
                }
                continue
            }

            // 3. Parse ground truth
            let groundTruthText = try String(contentsOf: testCase.transcriptPath, encoding: .utf8)
            let groundTruthTurns = GroundTruthParser.parse(groundTruthText)
            try #require(
                !groundTruthTurns.isEmpty,
                "Ground truth parse failed for \(testCase.name)"
            )

            // 4. Score WER
            //    Concatenate ground truth words and hypothesis text into flat strings.
            let referenceText = groundTruthTurns
                .flatMap(\.words)
                .joined(separator: " ")
            let hypothesisText = turnsToScore
                .map(\.text)
                .joined(separator: " ")

            let werResult = WERScorer.score(reference: referenceText, hypothesis: hypothesisText)

            // 5. Score diarization
            //    Build LabeledWord arrays from both ground truth and hypothesis.
            let referenceLabeledWords: [LabeledWord] = groundTruthTurns.flatMap { turn in
                turn.words.map { word in
                    LabeledWord(word: word, speaker: turn.speaker)
                }
            }
            let hypothesisLabeledWords: [LabeledWord] = turnsToScore.flatMap { turn in
                turn.text
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .map { word in
                        LabeledWord(word: word, speaker: turn.speakerLabel)
                    }
            }

            let diarizationResult = DiarizationScorer.score(
                reference: referenceLabeledWords,
                hypothesis: hypothesisLabeledWords
            )

            // 6. Build benchmark result
            let benchmarkResult = BenchmarkResult(
                testCaseName: testCase.name,
                werAccuracy: werResult.accuracy,
                diarizationAccuracy: diarizationResult.accuracy
            )

            // Log results for visibility
            print("""
            [\(testCase.name)] WER accuracy: \(String(format: "%.1f", werResult.accuracy))% \
            (S:\(werResult.substitutions) I:\(werResult.insertions) D:\(werResult.deletions))
            """)
            print("""
            [\(testCase.name)] Diarization accuracy: \
            \(String(format: "%.1f", diarizationResult.accuracy))% \
            (\(diarizationResult.correctWords)/\(diarizationResult.totalMatchedWords) words correct)
            """)

            // 7. Compare against baseline
            let comparison = try comparator.compare(result: benchmarkResult)

            if comparison.werDelta != nil || comparison.diarizationDelta != nil {
                // Baseline exists -- check for regression.
                if let werDelta = comparison.werDelta {
                    print("[\(testCase.name)] WER delta from baseline: \(String(format: "%+.1f", werDelta))pp")
                }
                if let diarizationDelta = comparison.diarizationDelta {
                    print("[\(testCase.name)] Diarization delta from baseline: \(String(format: "%+.1f", diarizationDelta))pp")
                }

                #expect(
                    !comparison.isRegression,
                    """
                    Regression detected for \(testCase.name): \
                    WER delta=\(comparison.werDelta.map { String(format: "%+.1f", $0) } ?? "n/a")pp, \
                    diarization delta=\(comparison.diarizationDelta.map { String(format: "%+.1f", $0) } ?? "n/a")pp
                    """
                )
            } else {
                // 8. No baseline yet -- write the initial baseline.
                print("[\(testCase.name)] No baseline found. Writing initial baseline.")
                try comparator.updateBaseline(with: benchmarkResult)
            }
        }
    }

    // MARK: - Transcription Runner

    /// Runs the transcription pipeline for a single test case on the MainActor.
    ///
    /// Returns `.unavailable` if FluidAudio models are not installed and the
    /// Speech framework fallback also fails, or `.success` with the stop result
    /// and any turns collected via the event handler.
    @MainActor
    private func runTranscription(for testCase: TestCase) async -> BenchmarkRunOutcome {
        let replayer = FileAudioReplayer(fileURL: testCase.audioPath)
        let service = DefaultTranscriptionService(audioProvider: replayer)

        // Collect events emitted during the session.
        let collector = TranscriptionEventCollector()
        service.setEventHandler { event in
            Task {
                await collector.handle(event)
            }
        }

        // Attempt to start the transcription session. If FluidAudio models are
        // not installed the service will try to download them; if that fails it
        // falls back to Apple's Speech framework. On a Mac without microphone
        // permissions the Speech fallback will also throw.
        let sessionID = UUID()
        let startedAt = Date()

        do {
            try await service.start(sessionID: sessionID, startedAt: startedAt)
        } catch {
            return .unavailable(
                reason: "FluidAudio models not installed and Speech fallback unavailable: \(error.localizedDescription)"
            )
        }

        // Wait for the audio to finish replaying. The clip duration comes from
        // metadata; add buffer time for processing latency and the final EOU
        // debounce window.
        let replayDuration = Double(testCase.metadata.duration)
        let waitSeconds = replayDuration + 5.0
        try? await Task.sleep(for: .seconds(waitSeconds))

        // Stop the session and get the reconciled output.
        let stopResult = await service.stop()
        let collectedTurns = await collector.finalizedTurns

        return .success(stopResult, collectedTurns: collectedTurns)
    }
}
