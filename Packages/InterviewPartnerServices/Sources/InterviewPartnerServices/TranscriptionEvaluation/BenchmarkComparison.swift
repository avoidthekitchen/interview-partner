import Foundation

public struct BenchmarkMetricComparison: Codable, Hashable, Sendable {
    public let metric: String
    public let baseline: Double
    public let candidate: Double
    public let delta: Double
    public let regression: Bool

    public init(metric: String, baseline: Double, candidate: Double, delta: Double, regression: Bool) {
        self.metric = metric
        self.baseline = baseline
        self.candidate = candidate
        self.delta = delta
        self.regression = regression
    }
}

public struct BenchmarkComparisonResult: Codable, Hashable, Sendable {
    public let baselineVariant: String
    public let candidateVariant: String
    public let fixtureComparisons: [String: [BenchmarkMetricComparison]]

    public init(
        baselineVariant: String,
        candidateVariant: String,
        fixtureComparisons: [String: [BenchmarkMetricComparison]]
    ) {
        self.baselineVariant = baselineVariant
        self.candidateVariant = candidateVariant
        self.fixtureComparisons = fixtureComparisons
    }
}

public enum BenchmarkComparison {
    public static func compare(
        baseline: TranscriptionBenchmarkReport,
        candidate: TranscriptionBenchmarkReport
    ) -> BenchmarkComparisonResult {
        let baselineFixtures = Dictionary(uniqueKeysWithValues: baseline.fixtures.map { ($0.fixtureID, $0) })
        let candidateFixtures = Dictionary(uniqueKeysWithValues: candidate.fixtures.map { ($0.fixtureID, $0) })

        var fixtureComparisons: [String: [BenchmarkMetricComparison]] = [:]
        for fixtureID in Set(baselineFixtures.keys).intersection(candidateFixtures.keys) {
            guard
                let baselineFixture = baselineFixtures[fixtureID],
                let candidateFixture = candidateFixtures[fixtureID]
            else { continue }

            let comparisons = allMetricNames.compactMap { metricName -> BenchmarkMetricComparison? in
                guard
                    let baselineValue = baselineFixture.metrics.value(named: metricName),
                    let candidateValue = candidateFixture.metrics.value(named: metricName)
                else { return nil }

                let delta = candidateValue - baselineValue
                return BenchmarkMetricComparison(
                    metric: metricName,
                    baseline: baselineValue,
                    candidate: candidateValue,
                    delta: delta,
                    regression: isRegression(metric: metricName, delta: delta)
                )
            }
            fixtureComparisons[fixtureID] = comparisons
        }

        return BenchmarkComparisonResult(
            baselineVariant: baseline.variant,
            candidateVariant: candidate.variant,
            fixtureComparisons: fixtureComparisons
        )
    }

    private static let allMetricNames = [
        "turn_boundary_mae_ms",
        "late_finalization_p95_ms",
        "split_merge_error_count",
        "expected_turn_recall",
        "actual_turn_precision",
        "missing_expected_turn_count",
        "extra_actual_turn_count",
        "session_coverage_ratio",
        "live_speaker_accuracy",
        "final_speaker_accuracy",
        "live_speaker_coverage_recall",
        "final_speaker_coverage_recall",
        "live_speaker_count_error",
        "final_speaker_count_error",
        "unclear_rate",
        "offline_runtime_rtf",
        "missing_speech_end_count",
    ]

    private static func isRegression(metric: String, delta: Double) -> Bool {
        switch metric {
        case
            "expected_turn_recall",
            "actual_turn_precision",
            "session_coverage_ratio",
            "live_speaker_accuracy",
            "final_speaker_accuracy",
            "live_speaker_coverage_recall",
            "final_speaker_coverage_recall":
            return delta < 0
        default:
            return delta > 0
        }
    }
}
