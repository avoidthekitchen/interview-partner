import Foundation
import Testing
@testable import InterviewPartnerServices

@Test func audioTapWorkTrackerWaitsForPendingBuffers() async throws {
    let tracker = AudioTapWorkTracker()
    let clock = ContinuousClock()

    tracker.begin()
    let start = clock.now
    let waiter = Task {
        await tracker.waitUntilIdle()
        return clock.now
    }

    try await Task.sleep(for: .milliseconds(50))
    tracker.end()

    let finished = await waiter.value
    #expect(start.duration(to: finished) >= .milliseconds(50))
    #expect(tracker.snapshot().pendingBuffers == 0)
}
