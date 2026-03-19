import Testing
@testable import InterviewPartnerServices

@Test func vadBoundaryTrackerConsumesCompletedWindow() {
    var tracker = VadBoundaryTracker()
    tracker.ingest(event: VadBoundaryEvent(kind: .speechStart, timeSeconds: 0.25))
    tracker.ingest(event: VadBoundaryEvent(kind: .speechEnd, timeSeconds: 0.8))

    let result = tracker.consumeBestWindow(
        audioDurationSeconds: 1.2,
        previousBoundarySeconds: 0,
        eouDebounceMs: 640
    )

    #expect(result.window.source == .vad)
    #expect(result.window.startSeconds == 0.25)
    #expect(result.window.endSeconds == 0.8)
    #expect(result.missedSpeechEnd == false)
}

@Test func vadBoundaryTrackerFallsBackWhenNoEventsExist() {
    var tracker = VadBoundaryTracker()

    let result = tracker.consumeBestWindow(
        audioDurationSeconds: 1.5,
        previousBoundarySeconds: 0.2,
        eouDebounceMs: 640
    )

    #expect(result.window.source == .debounceFallback)
    #expect(result.missedSpeechEnd == true)
}
