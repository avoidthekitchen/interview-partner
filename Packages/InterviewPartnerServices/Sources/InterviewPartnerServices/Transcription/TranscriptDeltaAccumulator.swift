import Foundation

struct TranscriptDeltaAccumulator: Sendable {
    private(set) var committedTranscript = ""

    mutating func reset() {
        committedTranscript = ""
    }

    func deltaText(from cumulativeTranscript: String) -> String {
        guard !committedTranscript.isEmpty else {
            return cumulativeTranscript
        }

        if cumulativeTranscript.hasPrefix(committedTranscript) {
            return String(cumulativeTranscript.dropFirst(committedTranscript.count))
        }

        let sharedPrefix = cumulativeTranscript.commonPrefix(with: committedTranscript)
        guard !sharedPrefix.isEmpty else {
            return cumulativeTranscript
        }

        return String(cumulativeTranscript.dropFirst(sharedPrefix.count))
    }

    mutating func commit(_ cumulativeTranscript: String) -> String {
        let delta = deltaText(from: cumulativeTranscript)
        committedTranscript = cumulativeTranscript
        return delta
    }
}
