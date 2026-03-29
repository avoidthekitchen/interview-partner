import Foundation

/// The result of comparing a benchmark result against a stored baseline.
public struct ComparisonResult: Sendable, Equatable {
    /// Whether the result represents a regression from the baseline.
    public let isRegression: Bool

    /// The difference in WER accuracy from baseline (positive = improvement, negative = regression).
    public let werDelta: Double?

    /// The difference in diarization accuracy from baseline (positive = improvement, negative = regression).
    public let diarizationDelta: Double?

    public init(isRegression: Bool, werDelta: Double?, diarizationDelta: Double?) {
        self.isRegression = isRegression
        self.werDelta = werDelta
        self.diarizationDelta = diarizationDelta
    }
}

/// Compares benchmark results against stored baselines and manages baseline persistence.
public struct BaselineComparator: Sendable {
    private let baselinePath: URL
    /// Minimum drop (in percentage points) before a run is flagged as a regression.
    /// Accounts for natural run-to-run variance in non-deterministic streaming ASR.
    private let regressionTolerancePP: Double

    public init(baselinePath: URL, regressionTolerancePP: Double = 5.0) {
        self.baselinePath = baselinePath
        self.regressionTolerancePP = regressionTolerancePP
    }

    /// Compares a benchmark result against the stored baseline for that test case.
    ///
    /// - If no baseline file exists, this is treated as the first run and no regression is reported.
    /// - If no baseline entry exists for the given test case name, no regression is reported.
    /// - A regression is detected if either WER accuracy or diarization accuracy drops below the baseline.
    ///
    /// - Parameter result: The benchmark result to compare.
    /// - Returns: A `ComparisonResult` indicating whether regression was detected.
    public func compare(result: BenchmarkResult) throws -> ComparisonResult {
        guard FileManager.default.fileExists(atPath: baselinePath.path) else {
            // First run: no baseline file yet, not a regression
            return ComparisonResult(isRegression: false, werDelta: nil, diarizationDelta: nil)
        }

        let data = try Data(contentsOf: baselinePath)
        let baseline = try JSONDecoder().decode(BaselineMetrics.self, from: data)

        guard let caseBaseline = baseline.results[result.testCaseName] else {
            // No baseline for this test case yet, not a regression
            return ComparisonResult(isRegression: false, werDelta: nil, diarizationDelta: nil)
        }

        let werDelta = result.werAccuracy - caseBaseline.werAccuracy
        let diarizationDelta = result.diarizationAccuracy - caseBaseline.diarizationAccuracy

        let isRegression = werDelta < -regressionTolerancePP
            || diarizationDelta < -regressionTolerancePP

        return ComparisonResult(
            isRegression: isRegression,
            werDelta: werDelta,
            diarizationDelta: diarizationDelta
        )
    }

    /// Reads the current baseline metrics from disk, or returns an empty baseline if the file doesn't exist.
    public func loadBaseline() throws -> BaselineMetrics {
        guard FileManager.default.fileExists(atPath: baselinePath.path) else {
            return BaselineMetrics()
        }
        let data = try Data(contentsOf: baselinePath)
        return try JSONDecoder().decode(BaselineMetrics.self, from: data)
    }

    /// Updates the baseline with a new benchmark result.
    ///
    /// Reads the existing baseline (or creates a new one), updates the entry for the given test case,
    /// and writes the result back to disk.
    ///
    /// - Parameter result: The benchmark result to store as the new baseline.
    public func updateBaseline(with result: BenchmarkResult) throws {
        var baseline = try loadBaseline()
        baseline.results[result.testCaseName] = CaseBaseline(
            werAccuracy: result.werAccuracy,
            diarizationAccuracy: result.diarizationAccuracy
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(baseline)
        try data.write(to: baselinePath)
    }
}
