import Testing
@testable import InterviewPartnerFeature

@Test func dominantSpeakerWinsEOUWindow() async throws {
    let segments = [
        DiarizedSegment(speakerIndex: 0, startTimeSeconds: 0.0, endTimeSeconds: 1.0, isFinal: true),
        DiarizedSegment(speakerIndex: 1, startTimeSeconds: 1.0, endTimeSeconds: 2.8, isFinal: true),
    ]

    let attribution = DominantSpeakerMatcher.attributeNextTurn(
        segments: segments,
        previousBoundarySeconds: 0.8,
        audioDurationSeconds: 3.6,
        eouDebounceMs: 640,
        speakerLabel: { "Speaker \($0)" }
    )

    #expect(attribution.speakerIndex == 1)
    #expect(attribution.speakerLabel == "Speaker 1")
    #expect(attribution.estimatedEndTimeSeconds == 2.96)
}

@Test func overlappingSpeakersRemainUnclear() async throws {
    let segments = [
        DiarizedSegment(speakerIndex: 0, startTimeSeconds: 0.0, endTimeSeconds: 1.9, isFinal: true),
        DiarizedSegment(speakerIndex: 1, startTimeSeconds: 0.2, endTimeSeconds: 1.8, isFinal: true),
    ]

    let attribution = DominantSpeakerMatcher.attributeNextTurn(
        segments: segments,
        previousBoundarySeconds: 0.0,
        audioDurationSeconds: 2.4,
        eouDebounceMs: 640,
        speakerLabel: { "Speaker \($0)" }
    )

    #expect(attribution.speakerIndex == nil)
    #expect(attribution.speakerLabel == "Unclear")
}

@Test func noSegmentsFallsBackToUnclear() async throws {
    let attribution = DominantSpeakerMatcher.attributeNextTurn(
        segments: [],
        previousBoundarySeconds: 0.0,
        audioDurationSeconds: 1.5,
        eouDebounceMs: 640,
        speakerLabel: { "Speaker \($0)" }
    )

    #expect(attribution.speakerIndex == nil)
    #expect(attribution.confidence == 0)
    #expect(attribution.speakerLabel == "Unclear")
}
