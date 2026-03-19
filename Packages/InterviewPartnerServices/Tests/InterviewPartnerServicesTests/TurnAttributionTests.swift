import Foundation
import Testing
@testable import InterviewPartnerServices

@Test func transcriptDeltaAccumulatorHandlesEarlierTokenRevision() {
    var accumulator = TranscriptDeltaAccumulator()

    #expect(accumulator.commit("I think we shipped") == "I think we shipped")
    #expect(accumulator.commit("I think we ship it yesterday") == " it yesterday")
}

@Test func liveTurnAssemblerMarksCompetingOverlapAsUnclear() {
    let result = LiveTurnAssembler.assembleTurn(
        sessionID: UUID(),
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        previousTurnEndTimeSeconds: nil,
        text: "I can take this",
        diarizationAvailable: true,
        window: UtteranceWindow(startSeconds: 0, endSeconds: 1, source: .vad),
        diarizationSegments: [
            DiarizedSegment(speakerIndex: 0, startTimeSeconds: 0, endTimeSeconds: 0.52, isFinal: true),
            DiarizedSegment(speakerIndex: 1, startTimeSeconds: 0.48, endTimeSeconds: 1.0, isFinal: true),
        ],
        gapThresholdSeconds: 10,
        tuning: .productionDefault
    )

    #expect(result.turn.speakerLabel == "Unclear")
}
