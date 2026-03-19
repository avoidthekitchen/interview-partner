import Foundation

enum BoundaryMetrics {
    static func matchedTurnCount(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Int {
        zip(actual, expected).reduce(into: 0) { count, pair in
            if normalize(pair.0.turn.text) == normalize(pair.1.text) {
                count += 1
            }
        }
    }

    static func meanAbsoluteBoundaryErrorMs(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Double {
        let pairs = zip(actual, expected)
        let diffs = pairs.map { pair in
            let startDiff = abs((pair.0.turn.startTimeSeconds ?? 0) - pair.1.startSeconds)
            let endDiff = abs((pair.0.turn.endTimeSeconds ?? 0) - pair.1.endSeconds)
            return ((startDiff + endDiff) / 2.0) * 1000.0
        }
        guard !diffs.isEmpty else { return 0 }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    static func lateFinalizationP95Ms(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Double {
        let delays = zip(actual, expected).map { pair in
            max(0, pair.0.finalizedAtSeconds - pair.1.endSeconds) * 1000.0
        }.sorted()

        guard !delays.isEmpty else { return 0 }
        let index = Int((Double(delays.count - 1) * 0.95).rounded(.up))
        return delays[min(index, delays.count - 1)]
    }

    static func splitMergeErrorCount(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Int {
        let baseDelta = abs(actual.count - expected.count)
        let mismatchedTexts = min(actual.count, expected.count) - matchedTurnCount(actual: actual, expected: expected)
        return baseDelta + mismatchedTexts
    }

    static func expectedTurnRecall(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Double {
        guard !expected.isEmpty else { return 1 }
        return Double(matchedTurnCount(actual: actual, expected: expected)) / Double(expected.count)
    }

    static func actualTurnPrecision(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Double {
        guard !actual.isEmpty else { return expected.isEmpty ? 1 : 0 }
        return Double(matchedTurnCount(actual: actual, expected: expected)) / Double(actual.count)
    }

    static func missingExpectedTurnCount(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Int {
        max(expected.count - matchedTurnCount(actual: actual, expected: expected), 0)
    }

    static func extraActualTurnCount(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Int {
        max(actual.count - matchedTurnCount(actual: actual, expected: expected), 0)
    }

    static func sessionCoverageRatio(
        actual: [BenchmarkTurn],
        expected: [ReplayExpectedTurn]
    ) -> Double {
        let actualCoverage = actual.compactMap(\.turn.endTimeSeconds).max() ?? 0
        let expectedCoverage = expected.map(\.endSeconds).max() ?? 0
        guard expectedCoverage > 0 else { return actualCoverage > 0 ? 1 : 0 }
        return min(max(actualCoverage / expectedCoverage, 0), 1)
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
