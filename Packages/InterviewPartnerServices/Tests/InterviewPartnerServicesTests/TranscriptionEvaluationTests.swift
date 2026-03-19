import Foundation
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
        #expect(after.metrics.finalSpeakerAccuracy >= before.metrics.finalSpeakerAccuracy)
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
        #expect(fixture.metrics.liveSpeakerAccuracy >= baselineFixture.metrics.liveSpeakerAccuracy)
        #expect(fixture.metrics.finalSpeakerAccuracy >= baselineFixture.metrics.finalSpeakerAccuracy)
        #expect(fixture.metrics.offlineRuntimeRTF <= 0.25)
    }
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
