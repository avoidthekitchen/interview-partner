import Foundation
import InterviewPartnerDomain
import Testing
@testable import InterviewPartnerServices

@Test func benchmarkRunnerShowsBoundaryImprovementWithVadAndOfflineReconciliation() throws {
    let fixtures = try TranscriptionBenchmarkRunner.loadFixtures(
        at: fixtureRoot(),
        fixtureSet: "baseline"
    )

    let baseline = TranscriptionBenchmarkRunner.run(
        fixtures: fixtures,
        variant: .phase1Baseline
    )
    let current = TranscriptionBenchmarkRunner.run(
        fixtures: fixtures,
        variant: .productionCurrent
    )

    let baselineByID = Dictionary(uniqueKeysWithValues: baseline.fixtures.map { ($0.fixtureID, $0) })
    let currentByID = Dictionary(uniqueKeysWithValues: current.fixtures.map { ($0.fixtureID, $0) })

    for fixtureID in baselineByID.keys {
        let before = try #require(baselineByID[fixtureID])
        let after = try #require(currentByID[fixtureID])
        #expect(after.metrics.turnBoundaryMAEMs <= before.metrics.turnBoundaryMAEMs)
        #expect(after.metrics.lateFinalizationP95Ms <= before.metrics.lateFinalizationP95Ms)
        #expect(after.metrics.splitMergeErrorCount <= before.metrics.splitMergeErrorCount)
        #expect(after.metrics.expectedTurnRecall >= before.metrics.expectedTurnRecall)
        #expect(after.metrics.actualTurnPrecision >= before.metrics.actualTurnPrecision)
        #expect(after.metrics.missingExpectedTurnCount <= before.metrics.missingExpectedTurnCount)
        #expect(after.metrics.extraActualTurnCount <= before.metrics.extraActualTurnCount)
        #expect(after.metrics.sessionCoverageRatio >= before.metrics.sessionCoverageRatio)
        #expect(after.metrics.finalSpeakerAccuracy >= before.metrics.finalSpeakerAccuracy)
        #expect(after.metrics.finalSpeakerCoverageRecall >= before.metrics.finalSpeakerCoverageRecall)
        #expect(after.metrics.finalSpeakerCountError <= before.metrics.finalSpeakerCountError)
    }
}

@Test func benchmarkOutputStaysWithinCheckedInToleranceEnvelope() throws {
    let fixtures = try TranscriptionBenchmarkRunner.loadFixtures(
        at: fixtureRoot(),
        fixtureSet: "baseline"
    )
    let current = TranscriptionBenchmarkRunner.run(
        fixtures: fixtures,
        variant: .productionCurrent
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let baseline = try decoder.decode(
        TranscriptionBenchmarkReport.self,
        from: Data(contentsOf: repoRoot().appendingPathComponent("rpi/evals/mobile_transcription/baseline_metrics.json"))
    )

    let baselineByID = Dictionary(uniqueKeysWithValues: baseline.fixtures.map { ($0.fixtureID, $0) })
    for fixture in current.fixtures {
        let baselineFixture = try #require(baselineByID[fixture.fixtureID])
        #expect(fixture.metrics.turnBoundaryMAEMs <= baselineFixture.metrics.turnBoundaryMAEMs)
        #expect(fixture.metrics.lateFinalizationP95Ms <= baselineFixture.metrics.lateFinalizationP95Ms)
        #expect(fixture.metrics.splitMergeErrorCount <= baselineFixture.metrics.splitMergeErrorCount)
        #expect(fixture.metrics.expectedTurnRecall >= baselineFixture.metrics.expectedTurnRecall)
        #expect(fixture.metrics.actualTurnPrecision >= baselineFixture.metrics.actualTurnPrecision)
        #expect(fixture.metrics.missingExpectedTurnCount <= baselineFixture.metrics.missingExpectedTurnCount)
        #expect(fixture.metrics.extraActualTurnCount <= baselineFixture.metrics.extraActualTurnCount)
        #expect(fixture.metrics.sessionCoverageRatio >= baselineFixture.metrics.sessionCoverageRatio)
        #expect(fixture.metrics.liveSpeakerAccuracy >= baselineFixture.metrics.liveSpeakerAccuracy)
        #expect(fixture.metrics.finalSpeakerAccuracy >= baselineFixture.metrics.finalSpeakerAccuracy)
        #expect(fixture.metrics.liveSpeakerCoverageRecall >= baselineFixture.metrics.liveSpeakerCoverageRecall)
        #expect(fixture.metrics.finalSpeakerCoverageRecall >= baselineFixture.metrics.finalSpeakerCoverageRecall)
        #expect(fixture.metrics.liveSpeakerCountError <= baselineFixture.metrics.liveSpeakerCountError)
        #expect(fixture.metrics.finalSpeakerCountError <= baselineFixture.metrics.finalSpeakerCountError)
        #expect(fixture.metrics.offlineRuntimeRTF <= 0.25)
    }
}

@Test func coverageMetricsExposeTurnTruncation() {
    let expected = [
        ReplayExpectedTurn(text: "one", speakerLabel: "Speaker A", startSeconds: 0, endSeconds: 1),
        ReplayExpectedTurn(text: "two", speakerLabel: "Speaker B", startSeconds: 2, endSeconds: 3),
        ReplayExpectedTurn(text: "three", speakerLabel: "Speaker C", startSeconds: 4, endSeconds: 5),
    ]
    let actual = [
        BenchmarkTurn(
            turn: TranscriptTurn(
                speakerLabel: "Speaker A",
                text: "one",
                timestamp: Date(timeIntervalSinceReferenceDate: 1),
                isFinal: true,
                startTimeSeconds: 0,
                endTimeSeconds: 1,
                speakerMatchConfidence: 1,
                speakerLabelIsProvisional: false
            ),
            finalizedAtSeconds: 1.2
        )
    ]

    #expect(abs(BoundaryMetrics.expectedTurnRecall(actual: actual, expected: expected) - (1.0 / 3.0)) < 0.0001)
    #expect(BoundaryMetrics.missingExpectedTurnCount(actual: actual, expected: expected) == 2)
    #expect(abs(BoundaryMetrics.sessionCoverageRatio(actual: actual, expected: expected) - 0.2) < 0.0001)
    #expect(
        SpeakerMetrics.speakerCountError(
            actual: actual,
            expected: expected,
            label: { (turn: BenchmarkTurn) in turn.turn.speakerLabel }
        ) == 2
    )
}

@Test func audioIntegrationRunnerReturnsFailureReportWhenFixtureEvaluationThrows() async throws {
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    let fixture = ReplayFixture(
        fixtureID: "missing_audio_fixture",
        fixtureSet: "local_audio_stable",
        description: "Missing audio file fixture",
        audioFileName: "missing.m4a",
        frames: [],
        expectedTurns: [
            ReplayExpectedTurn(text: "hello", speakerLabel: "Speaker A", startSeconds: 0, endSeconds: 2),
            ReplayExpectedTurn(text: "world", speakerLabel: "Speaker B", startSeconds: 2, endSeconds: 4),
        ],
        offlineDiarizationSegments: [],
        offlineRuntimeSeconds: 0
    )

    let report = try await AudioIntegrationBenchmarkRunner.run(
        fixtures: [fixture],
        fixturesRoot: tempRoot,
        variant: .phase1Baseline
    )

    let evaluatedFixture = try #require(report.fixtures.first)
    #expect(evaluatedFixture.metrics.actualLiveTurnCount == 0)
    #expect(evaluatedFixture.metrics.expectedTurnRecall == 0)
    #expect(evaluatedFixture.metrics.missingExpectedTurnCount == 2)
    #expect(evaluatedFixture.notes.contains { $0.contains("failed before producing a transcript") })
    #expect(evaluatedFixture.notes.contains { $0.contains("missing.m4a") })
}

private func fixtureRoot() -> URL {
    Bundle.module.resourceURL!
}

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
