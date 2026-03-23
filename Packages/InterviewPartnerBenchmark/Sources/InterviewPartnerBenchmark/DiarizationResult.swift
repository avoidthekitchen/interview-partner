/// The result of a diarization scoring operation.
public struct DiarizationResult: Sendable {
    /// Speaker attribution accuracy as a percentage (0-100).
    public let accuracy: Double
    /// Number of matched words where the speaker label was correct.
    public let correctWords: Int
    /// Total number of matched word pairs (equal or substitution alignments).
    public let totalMatchedWords: Int

    public init(accuracy: Double, correctWords: Int, totalMatchedWords: Int) {
        self.accuracy = accuracy
        self.correctWords = correctWords
        self.totalMatchedWords = totalMatchedWords
    }
}
