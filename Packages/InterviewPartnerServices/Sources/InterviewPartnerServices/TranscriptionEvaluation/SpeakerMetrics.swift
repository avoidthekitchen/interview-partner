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

    static func expectedSpeakerCount(expected: [ReplayExpectedTurn]) -> Int {
        Set(expected.map(\.speakerLabel).map(normalize)).count
    }

    static func distinctSpeakerCount<TurnType>(
        actual: [TurnType],
        label: (TurnType) -> String
    ) -> Int {
        Set(actual.map(label).map(normalize).filter { $0 != "unclear" }).count
    }

    static func speakerCoverageRecall<TurnType>(
        actual: [TurnType],
        expected: [ReplayExpectedTurn],
        label: (TurnType) -> String
    ) -> Double {
        let expectedLabels = Set(expected.map(\.speakerLabel).map(normalize))
        guard !expectedLabels.isEmpty else { return 1 }
        let actualLabels = Set(actual.map(label).map(normalize).filter { $0 != "unclear" })
        return Double(expectedLabels.intersection(actualLabels).count) / Double(expectedLabels.count)
    }

    static func speakerCountError<TurnType>(
        actual: [TurnType],
        expected: [ReplayExpectedTurn],
        label: (TurnType) -> String
    ) -> Int {
        abs(distinctSpeakerCount(actual: actual, label: label) - expectedSpeakerCount(expected: expected))
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
