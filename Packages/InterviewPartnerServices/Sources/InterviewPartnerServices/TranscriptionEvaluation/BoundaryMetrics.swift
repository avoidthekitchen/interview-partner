import Foundation

enum BoundaryMetrics {
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
        let mismatchedTexts = zip(actual, expected).reduce(into: 0) { count, pair in
            if normalize(pair.0.turn.text) != normalize(pair.1.text) {
                count += 1
            }
        }
        return baseDelta + mismatchedTexts
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
