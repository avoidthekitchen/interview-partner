import Foundation

enum SpeakerMetrics {
    static func accuracy<TurnType>(
        actual: [TurnType],
        expected: [ReplayExpectedTurn],
        label: (TurnType) -> String
    ) -> Double {
        let pairs = Array(zip(actual, expected))
        guard !pairs.isEmpty else { return 0 }

        let matches = pairs.reduce(into: 0) { count, pair in
            if normalize(label(pair.0)) == normalize(pair.1.speakerLabel) {
                count += 1
            }
        }
        return Double(matches) / Double(pairs.count)
    }

    static func unclearRate<TurnType>(
        actual: [TurnType],
        label: (TurnType) -> String
    ) -> Double {
        guard !actual.isEmpty else { return 0 }
        let unclearCount = actual.filter { normalize(label($0)) == "unclear" }.count
        return Double(unclearCount) / Double(actual.count)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
