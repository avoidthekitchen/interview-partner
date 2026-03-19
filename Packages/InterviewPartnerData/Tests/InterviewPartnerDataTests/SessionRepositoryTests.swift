import Foundation
import Testing
import InterviewPartnerDomain
@testable import InterviewPartnerData

@MainActor
@Test func createSessionSeedsQuestionStatusesAndSummary() throws {
    let container = try InterviewPartnerModelContainer.make(inMemoryOnly: true)
    let repository = SwiftDataSessionRepository(modelContainer: container)

    let record = try repository.createSession(
        guideSnapshot: GuideSnapshot(
            id: UUID(),
            name: "Discovery",
            goal: "Understand the workflow.",
            createdAt: .now,
            questions: [
                GuideSnapshotQuestion(
                    id: UUID(),
                    text: "Walk me through your last interview.",
                    priority: .mustCover,
                    orderIndex: 0,
                    subPrompts: []
                ),
                GuideSnapshotQuestion(
                    id: UUID(),
                    text: "What slowed you down?",
                    priority: .shouldCover,
                    orderIndex: 1,
                    subPrompts: []
                ),
            ]
        ),
        participantLabel: "Taylor"
    )

    let summaries = try repository.fetchSessions()

    #expect(record.participantLabel == "Taylor")
    #expect(record.questionStatuses.count == 2)
    #expect(record.questionStatuses.allSatisfy { $0.status == .notStarted })
    #expect(summaries.count == 1)
    #expect(summaries.first?.mustCoverQuestionCount == 1)
}

@MainActor
@Test func sessionRepositoryPersistsIncrementalSessionUpdates() throws {
    let container = try InterviewPartnerModelContainer.make(inMemoryOnly: true)
    let repository = SwiftDataSessionRepository(modelContainer: container)
    let questionID = UUID()

    let created = try repository.createSession(
        guideSnapshot: GuideSnapshot(
            id: UUID(),
            name: "Behavioral",
            goal: "Assess depth.",
            createdAt: .now,
            questions: [
                GuideSnapshotQuestion(
                    id: questionID,
                    text: "Tell me about a launch.",
                    priority: .mustCover,
                    orderIndex: 0,
                    subPrompts: []
                ),
            ]
        ),
        participantLabel: nil
    )

    let turn = TranscriptTurn(
        speakerLabel: "Speaker A",
        text: "We launched in phases.",
        timestamp: .now,
        isFinal: true,
        startTimeSeconds: 0,
        endTimeSeconds: 4,
        speakerMatchConfidence: 0.82,
        speakerLabelIsProvisional: true
    )
    try repository.appendTranscriptTurn(turn, to: created.id)

    let gap = TranscriptGap(
        sessionID: created.id,
        startTimestamp: .now,
        endTimestamp: .now.addingTimeInterval(12),
        reason: .transcriptionUnavailable
    )
    try repository.appendTranscriptGap(gap, to: created.id)

    let status = QuestionAnswerStatus(questionID: questionID, status: .answered)
    try repository.upsertQuestionStatus(status, for: created.id)

    let note = AdHocNote(text: "Probe onboarding path.", timestamp: .now)
    try repository.appendAdHocNote(note, to: created.id)

    let finalized = try repository.finalizeSession(
        id: created.id,
        endedAt: .now.addingTimeInterval(300),
        reconciledTurns: [
            TranscriptTurn(
                id: turn.id,
                speakerLabel: "Speaker B",
                text: turn.text,
                timestamp: turn.timestamp,
                isFinal: true,
                startTimeSeconds: turn.startTimeSeconds,
                endTimeSeconds: turn.endTimeSeconds,
                speakerMatchConfidence: 0.91,
                speakerLabelIsProvisional: false
            ),
        ]
    )

    let pendingExports = try repository.fetchPendingExportSessions()
    let edited = try repository.updateTranscriptTurn(
        TranscriptTurn(
            id: turn.id,
            speakerLabel: "Speaker B",
            text: "We launched in measured phases.",
            timestamp: turn.timestamp,
            isFinal: true,
            startTimeSeconds: turn.startTimeSeconds,
            endTimeSeconds: turn.endTimeSeconds,
            speakerMatchConfidence: 0.91,
            speakerLabelIsProvisional: false
        ),
        in: created.id
    )
    let renamed = try repository.renameSpeakerLabel(
        in: created.id,
        from: "Speaker B",
        to: "Candidate"
    )
    try repository.recordExportAttempt(for: created.id, at: .now)
    let completed = try repository.markExportCompleted(for: created.id)

    #expect(finalized.transcriptTurns.count == 1)
    #expect(finalized.transcriptTurns.first?.speakerLabel == "Speaker B")
    #expect(finalized.transcriptTurns.first?.speakerLabelIsProvisional == false)
    #expect(finalized.hasPendingExport == true)
    #expect(finalized.transcriptGaps.count == 1)
    #expect(finalized.adHocNotes.count == 1)
    #expect(finalized.questionStatuses.first?.status == .answered)
    #expect(finalized.endedAt != nil)
    #expect(pendingExports.count == 1)
    #expect(edited.transcriptTurns.first?.text == "We launched in measured phases.")
    #expect(renamed.transcriptTurns.first?.speakerLabel == "Candidate")
    #expect(completed.hasPendingExport == false)
}
