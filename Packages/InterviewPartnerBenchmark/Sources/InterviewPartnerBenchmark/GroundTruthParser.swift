import Foundation

/// A single turn in a ground truth transcript.
public struct TranscriptTurn: Sendable, Equatable {
    /// The timestamp string, e.g. "00:00:02".
    public let timestamp: String
    /// The speaker label, e.g. "Speaker 1".
    public let speaker: String
    /// The individual words spoken in this turn (preserving original punctuation).
    public let words: [String]
}

/// Parses ground truth transcripts in the timestamped speaker-label format.
///
/// Expected format:
/// ```
/// 00:00:02
/// Speaker 1: Hey there folks.
/// 00:00:34
/// Speaker 2: Yes, and that was the hope.
/// ```
public enum GroundTruthParser {

    /// Parse a transcript string into an array of ``TranscriptTurn`` values.
    public static func parse(_ text: String) -> [TranscriptTurn] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var turns: [TranscriptTurn] = []
        var index = 0

        while index < lines.count - 1 {
            let timestampLine = lines[index]

            // A timestamp line matches HH:MM:SS
            guard timestampLine.range(
                of: #"^\d{2}:\d{2}:\d{2}$"#,
                options: .regularExpression
            ) != nil else {
                index += 1
                continue
            }

            let speakerLine = lines[index + 1]

            guard let colonRange = speakerLine.range(of: ": ") else {
                index += 1
                continue
            }

            let speaker = String(speakerLine[speakerLine.startIndex..<colonRange.lowerBound])
            let spokenText = String(speakerLine[colonRange.upperBound...])
            let words = spokenText
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            turns.append(TranscriptTurn(
                timestamp: timestampLine,
                speaker: speaker,
                words: words
            ))

            index += 2
        }

        return turns
    }
}
