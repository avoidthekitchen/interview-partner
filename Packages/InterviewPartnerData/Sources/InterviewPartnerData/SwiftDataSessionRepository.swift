import Foundation
import OSLog
import SwiftData
import InterviewPartnerDomain

@MainActor
public final class SwiftDataSessionRepository: SessionRepository {
    private let modelContainer: ModelContainer
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "SessionRepository"
    )

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func fetchSessions() throws -> [SessionSummary] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\Session.startedAt, order: .reverse)]
        )

        return try modelContainer.mainContext.fetch(descriptor).map { session in
            let mustCoverQuestionIDs = Set(
                session.guideSnapshot.questions
                    .filter { $0.priority == .mustCover }
                    .map(\.id)
            )
            let answeredMustCoverCount = session.questionStatuses.filter { status in
                mustCoverQuestionIDs.contains(status.questionID) && status.status == .answered
            }.count

            return SessionSummary(
                id: session.id,
                guideName: session.guideSnapshot.name,
                participantLabel: session.participantLabel,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                mustCoverQuestionCount: mustCoverQuestionIDs.count,
                answeredMustCoverCount: answeredMustCoverCount,
                hasPendingExport: !session.exportQueueEntries.isEmpty
            )
        }
    }

    public func fetchSession(id: UUID) throws -> SessionRecord? {
        try fetchSessionModel(id: id).map(Self.record(from:))
    }

    public func fetchPendingExportSessions() throws -> [SessionRecord] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\Session.startedAt, order: .reverse)]
        )

        return try modelContainer.mainContext.fetch(descriptor)
            .filter { !$0.exportQueueEntries.isEmpty }
            .map(Self.record(from:))
    }

    @discardableResult
    public func createSession(
        guideSnapshot: GuideSnapshot,
        participantLabel: String?
    ) throws -> SessionRecord {
        let questionStatuses = guideSnapshot.questions.map { question in
            QuestionStatus(
                questionID: question.id,
                status: .notStarted
            )
        }
        let session = Session(
            guideSnapshot: guideSnapshot,
            participantLabel: participantLabel,
            questionStatuses: questionStatuses
        )
        modelContainer.mainContext.insert(session)
        try saveContext("create session")
        return Self.record(from: session)
    }

    public func appendTranscriptTurn(_ turn: InterviewPartnerDomain.TranscriptTurn, to sessionID: UUID) throws {
        let session = try requireSession(id: sessionID)
        let turnModel = TranscriptTurn(
            id: turn.id,
            speakerLabel: turn.speakerLabel,
            text: turn.text,
            timestamp: turn.timestamp,
            isFinal: turn.isFinal,
            startTimeSeconds: turn.startTimeSeconds,
            endTimeSeconds: turn.endTimeSeconds,
            speakerMatchConfidence: turn.speakerMatchConfidence,
            speakerLabelIsProvisional: turn.speakerLabelIsProvisional,
            session: session
        )
        modelContainer.mainContext.insert(turnModel)
        session.transcriptTurns.append(turnModel)
        try saveContext("append transcript turn")
    }

    public func appendTranscriptGap(_ gap: InterviewPartnerDomain.TranscriptGap, to sessionID: UUID) throws {
        let session = try requireSession(id: sessionID)
        let gapModel = TranscriptGap(
            id: gap.id,
            sessionID: gap.sessionID,
            startTimestamp: gap.startTimestamp,
            endTimestamp: gap.endTimestamp,
            reason: gap.reason,
            session: session
        )
        modelContainer.mainContext.insert(gapModel)
        session.transcriptGaps.append(gapModel)
        try saveContext("append transcript gap")
    }

    public func upsertQuestionStatus(_ status: QuestionAnswerStatus, for sessionID: UUID) throws {
        let session = try requireSession(id: sessionID)

        if let existing = session.questionStatuses.first(where: { $0.questionID == status.questionID }) {
            existing.status = status.status
            existing.aiScore = status.aiScore
        } else {
            let newStatus = QuestionStatus(
                id: status.id,
                questionID: status.questionID,
                status: status.status,
                aiScore: status.aiScore,
                session: session
            )
            modelContainer.mainContext.insert(newStatus)
            session.questionStatuses.append(newStatus)
        }

        try saveContext("upsert question status")
    }

    public func appendAdHocNote(_ note: InterviewPartnerDomain.AdHocNote, to sessionID: UUID) throws {
        let session = try requireSession(id: sessionID)
        let noteModel = AdHocNote(
            id: note.id,
            text: note.text,
            timestamp: note.timestamp,
            session: session
        )
        modelContainer.mainContext.insert(noteModel)
        session.adHocNotes.append(noteModel)
        try saveContext("append ad hoc note")
    }

    public func updateTranscriptTurn(
        _ turn: InterviewPartnerDomain.TranscriptTurn,
        in sessionID: UUID
    ) throws -> SessionRecord {
        let session = try requireSession(id: sessionID)
        guard let existing = session.transcriptTurns.first(where: { $0.id == turn.id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        existing.speakerLabel = turn.speakerLabel
        existing.text = turn.text
        existing.timestamp = turn.timestamp
        existing.isFinal = turn.isFinal
        existing.startTimeSeconds = turn.startTimeSeconds
        existing.endTimeSeconds = turn.endTimeSeconds
        existing.speakerMatchConfidence = turn.speakerMatchConfidence
        existing.speakerLabelIsProvisional = turn.speakerLabelIsProvisional

        try saveContext("update transcript turn")
        logger.info(
            "Updated transcript turn \(turn.id.uuidString, privacy: .public) in session \(sessionID.uuidString, privacy: .public)"
        )
        return Self.record(from: session)
    }

    public func renameSpeakerLabel(
        in sessionID: UUID,
        from originalLabel: String,
        to newLabel: String
    ) throws -> SessionRecord {
        let session = try requireSession(id: sessionID)
        let trimmedLabel = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            throw NSError(
                domain: "InterviewPartnerData.SessionRepository",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Speaker names cannot be empty."]
            )
        }

        for turn in session.transcriptTurns where turn.speakerLabel == originalLabel {
            turn.speakerLabel = trimmedLabel
            turn.speakerLabelIsProvisional = false
        }

        try saveContext("rename speaker label")
        logger.info(
            "Renamed speaker label in session \(sessionID.uuidString, privacy: .public) from \(originalLabel, privacy: .public) to \(trimmedLabel, privacy: .public)"
        )
        return Self.record(from: session)
    }

    public func finalizeSession(
        id: UUID,
        endedAt: Date,
        reconciledTurns: [InterviewPartnerDomain.TranscriptTurn]
    ) throws -> SessionRecord {
        let session = try requireSession(id: id)
        session.endedAt = endedAt

        let turnsByID = Dictionary(uniqueKeysWithValues: session.transcriptTurns.map { ($0.id, $0) })
        for turn in reconciledTurns {
            guard let existing = turnsByID[turn.id] else { continue }
            existing.speakerLabel = turn.speakerLabel
            existing.text = turn.text
            existing.timestamp = turn.timestamp
            existing.isFinal = turn.isFinal
            existing.startTimeSeconds = turn.startTimeSeconds
            existing.endTimeSeconds = turn.endTimeSeconds
            existing.speakerMatchConfidence = turn.speakerMatchConfidence
            existing.speakerLabelIsProvisional = turn.speakerLabelIsProvisional
        }

        if session.exportQueueEntries.isEmpty {
            let queueEntry = ExportQueueEntry(
                sessionID: id,
                queuedAt: .now,
                attemptCount: 0,
                lastAttemptAt: nil,
                session: session
            )
            modelContainer.mainContext.insert(queueEntry)
            session.exportQueueEntries.append(queueEntry)
            logger.info(
                "Created export queue entry \(queueEntry.id.uuidString, privacy: .public) for session \(id.uuidString, privacy: .public)"
            )
        }

        try saveContext("finalize session")
        return Self.record(from: session)
    }

    public func recordExportAttempt(for sessionID: UUID, at attemptedAt: Date) throws {
        let session = try requireSession(id: sessionID)
        guard let queueEntry = session.exportQueueEntries.first else { return }
        queueEntry.attemptCount += 1
        queueEntry.lastAttemptAt = attemptedAt
        try saveContext("record export attempt")
        logger.info(
            "Recorded export attempt \(queueEntry.attemptCount, privacy: .public) for session \(sessionID.uuidString, privacy: .public)"
        )
    }

    public func markExportCompleted(for sessionID: UUID) throws -> SessionRecord {
        let session = try requireSession(id: sessionID)
        for queueEntry in session.exportQueueEntries {
            modelContainer.mainContext.delete(queueEntry)
        }
        session.exportQueueEntries.removeAll()
        try saveContext("mark export completed")
        logger.info(
            "Cleared export queue for session \(sessionID.uuidString, privacy: .public)"
        )
        return Self.record(from: session)
    }

    private func fetchSessionModel(id: UUID) throws -> Session? {
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContainer.mainContext.fetch(descriptor).first
    }

    private func requireSession(id: UUID) throws -> Session {
        guard let session = try fetchSessionModel(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return session
    }

    private func saveContext(_ operation: String) throws {
        do {
            try modelContainer.mainContext.save()
        } catch {
            logger.error(
                "SwiftData save failed during \(operation, privacy: .public). Retrying once. Error: \(error.localizedDescription, privacy: .public)"
            )

            do {
                try modelContainer.mainContext.save()
                logger.info(
                    "SwiftData retry succeeded during \(operation, privacy: .public)"
                )
            } catch {
                logger.error(
                    "SwiftData retry failed during \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }
    }

    private static func record(from session: Session) -> SessionRecord {
        SessionRecord(
            id: session.id,
            guideSnapshot: session.guideSnapshot,
            participantLabel: session.participantLabel,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            transcriptTurns: session.transcriptTurns
                .sorted { $0.timestamp < $1.timestamp }
                .map(Self.domainTurn(from:)),
            transcriptGaps: session.transcriptGaps
                .sorted { $0.startTimestamp < $1.startTimestamp }
                .map(Self.domainGap(from:)),
            questionStatuses: session.questionStatuses
                .map(Self.domainStatus(from:))
                .sorted { $0.questionID.uuidString < $1.questionID.uuidString },
            adHocNotes: session.adHocNotes
                .sorted { $0.timestamp < $1.timestamp }
                .map(Self.domainNote(from:)),
            hasPendingExport: !session.exportQueueEntries.isEmpty
        )
    }

    private static func domainTurn(from turn: TranscriptTurn) -> InterviewPartnerDomain.TranscriptTurn {
        InterviewPartnerDomain.TranscriptTurn(
            id: turn.id,
            speakerLabel: turn.speakerLabel,
            text: turn.text,
            timestamp: turn.timestamp,
            isFinal: turn.isFinal,
            startTimeSeconds: turn.startTimeSeconds,
            endTimeSeconds: turn.endTimeSeconds,
            speakerMatchConfidence: turn.speakerMatchConfidence,
            speakerLabelIsProvisional: turn.speakerLabelIsProvisional
        )
    }

    private static func domainGap(from gap: TranscriptGap) -> InterviewPartnerDomain.TranscriptGap {
        InterviewPartnerDomain.TranscriptGap(
            id: gap.id,
            sessionID: gap.sessionID,
            startTimestamp: gap.startTimestamp,
            endTimestamp: gap.endTimestamp,
            reason: gap.reason
        )
    }

    private static func domainStatus(from status: QuestionStatus) -> QuestionAnswerStatus {
        QuestionAnswerStatus(
            id: status.id,
            questionID: status.questionID,
            status: status.status,
            aiScore: status.aiScore
        )
    }

    private static func domainNote(from note: AdHocNote) -> InterviewPartnerDomain.AdHocNote {
        InterviewPartnerDomain.AdHocNote(
            id: note.id,
            text: note.text,
            timestamp: note.timestamp
        )
    }
}
