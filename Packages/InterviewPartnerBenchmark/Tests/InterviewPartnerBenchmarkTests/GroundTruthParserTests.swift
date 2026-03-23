import Testing
@testable import InterviewPartnerBenchmark

@Suite("GroundTruthParser Tests")
struct GroundTruthParserTests {

    @Test("Parses a two-turn transcript with timestamps and speaker labels")
    func parseTwoTurnTranscript() {
        let input = """
        00:00:02
        Speaker 1: Hey there folks. It is Tuesday.
        00:00:34
        Speaker 2: Yes, and that was the hope.
        """

        let turns = GroundTruthParser.parse(input)

        #expect(turns.count == 2)

        #expect(turns[0].timestamp == "00:00:02")
        #expect(turns[0].speaker == "Speaker 1")
        #expect(turns[0].words == ["Hey", "there", "folks.", "It", "is", "Tuesday."])

        #expect(turns[1].timestamp == "00:00:34")
        #expect(turns[1].speaker == "Speaker 2")
        #expect(turns[1].words == ["Yes,", "and", "that", "was", "the", "hope."])
    }
}
