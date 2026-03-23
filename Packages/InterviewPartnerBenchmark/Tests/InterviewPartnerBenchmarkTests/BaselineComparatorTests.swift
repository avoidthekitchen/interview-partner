import Testing
import Foundation
@testable import InterviewPartnerBenchmark

@Suite("BaselineComparator")
struct BaselineComparatorTests {

    @Test("Detects regression when score is below stored baseline")
    func detectsRegression() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineComparatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselinePath = tempDir.appendingPathComponent("baseline_metrics.json")

        // Write a baseline with known good scores
        let baseline = BaselineMetrics(results: [
            "test-case-1": CaseBaseline(werAccuracy: 80.0, diarizationAccuracy: 85.0)
        ])
        let data = try JSONEncoder().encode(baseline)
        try data.write(to: baselinePath)

        let comparator = BaselineComparator(baselinePath: baselinePath)

        // Result with WER accuracy below baseline (regression)
        let result = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 70.0,
            diarizationAccuracy: 85.0
        )

        let comparison = try comparator.compare(result: result)
        #expect(comparison.isRegression == true)
        #expect(comparison.werDelta == -10.0)
        #expect(comparison.diarizationDelta == 0.0)
    }

    @Test("Detects diarization regression even when WER improves")
    func detectsDiarizationRegression() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineComparatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselinePath = tempDir.appendingPathComponent("baseline_metrics.json")
        let baseline = BaselineMetrics(results: [
            "test-case-1": CaseBaseline(werAccuracy: 80.0, diarizationAccuracy: 85.0)
        ])
        try JSONEncoder().encode(baseline).write(to: baselinePath)

        let comparator = BaselineComparator(baselinePath: baselinePath)

        let result = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 90.0,
            diarizationAccuracy: 75.0
        )

        let comparison = try comparator.compare(result: result)
        #expect(comparison.isRegression == true)
        #expect(comparison.werDelta == 10.0)
        #expect(comparison.diarizationDelta == -10.0)
    }

    @Test("Passing scores do not trigger regression")
    func passingScoresNoRegression() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineComparatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselinePath = tempDir.appendingPathComponent("baseline_metrics.json")

        let baseline = BaselineMetrics(results: [
            "test-case-1": CaseBaseline(werAccuracy: 80.0, diarizationAccuracy: 85.0)
        ])
        let data = try JSONEncoder().encode(baseline)
        try data.write(to: baselinePath)

        let comparator = BaselineComparator(baselinePath: baselinePath)

        // Equal scores
        let equalResult = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 80.0,
            diarizationAccuracy: 85.0
        )
        let equalComparison = try comparator.compare(result: equalResult)
        #expect(equalComparison.isRegression == false)

        // Improved scores
        let improvedResult = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 90.0,
            diarizationAccuracy: 95.0
        )
        let improvedComparison = try comparator.compare(result: improvedResult)
        #expect(improvedComparison.isRegression == false)
        #expect(improvedComparison.werDelta == 10.0)
        #expect(improvedComparison.diarizationDelta == 10.0)
    }

    @Test("Missing baseline file does not report regression (first run)")
    func missingBaselineSucceeds() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineComparatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Point to a non-existent baseline file
        let baselinePath = tempDir.appendingPathComponent("baseline_metrics.json")
        let comparator = BaselineComparator(baselinePath: baselinePath)

        let result = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 75.0,
            diarizationAccuracy: 80.0
        )

        let comparison = try comparator.compare(result: result)
        #expect(comparison.isRegression == false)
        #expect(comparison.werDelta == nil)
        #expect(comparison.diarizationDelta == nil)
    }

    @Test("Updating baseline writes new results to disk")
    func updateBaseline() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineComparatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baselinePath = tempDir.appendingPathComponent("baseline_metrics.json")
        let comparator = BaselineComparator(baselinePath: baselinePath)

        // Update with first result (no existing baseline file)
        let result1 = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 75.5,
            diarizationAccuracy: 82.3
        )
        try comparator.updateBaseline(with: result1)

        // Verify baseline was written
        let loaded = try comparator.loadBaseline()
        #expect(loaded.results.count == 1)
        let caseBaseline = try #require(loaded.results["test-case-1"])
        #expect(caseBaseline.werAccuracy == 75.5)
        #expect(caseBaseline.diarizationAccuracy == 82.3)

        // Update with a second test case
        let result2 = BenchmarkResult(
            testCaseName: "test-case-2",
            werAccuracy: 90.0,
            diarizationAccuracy: 88.0
        )
        try comparator.updateBaseline(with: result2)

        // Verify both entries exist
        let reloaded = try comparator.loadBaseline()
        #expect(reloaded.results.count == 2)
        #expect(reloaded.results["test-case-1"]?.werAccuracy == 75.5)
        #expect(reloaded.results["test-case-2"]?.werAccuracy == 90.0)

        // Update existing test case with new score
        let result1Updated = BenchmarkResult(
            testCaseName: "test-case-1",
            werAccuracy: 80.0,
            diarizationAccuracy: 85.0
        )
        try comparator.updateBaseline(with: result1Updated)

        let final = try comparator.loadBaseline()
        #expect(final.results.count == 2)
        #expect(final.results["test-case-1"]?.werAccuracy == 80.0)
        #expect(final.results["test-case-1"]?.diarizationAccuracy == 85.0)
    }
}
