/// A word paired with its speaker attribution label.
public struct LabeledWord: Sendable {
    public let word: String
    public let speaker: String

    public init(word: String, speaker: String) {
        self.word = word
        self.speaker = speaker
    }
}
