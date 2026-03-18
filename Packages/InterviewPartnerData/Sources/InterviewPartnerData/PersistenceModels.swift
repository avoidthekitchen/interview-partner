import Foundation
import SwiftData
import InterviewPartnerDomain

@Model
public final class Guide {
    public var id: UUID
    public var name: String
    public var goal: String
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Question.guide)
    public var questions: [Question]

    public init(
        id: UUID = UUID(),
        name: String,
        goal: String,
        createdAt: Date = .now,
        questions: [Question] = []
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.createdAt = createdAt
        self.questions = questions
    }
}

@Model
public final class Question {
    public var id: UUID
    public var text: String
    public var priority: QuestionPriority
    public var orderIndex: Int
    public var subPrompts: [String]
    public var guide: Guide?

    public init(
        id: UUID = UUID(),
        text: String,
        priority: QuestionPriority,
        orderIndex: Int,
        subPrompts: [String] = [],
        guide: Guide? = nil
    ) {
        self.id = id
        self.text = text
        self.priority = priority
        self.orderIndex = orderIndex
        self.subPrompts = subPrompts
        self.guide = guide
    }
}

@Model
public final class Session {
    public var id: UUID
    public var guideSnapshot: GuideSnapshot
    public var participantLabel: String?
    public var startedAt: Date
    public var endedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \QuestionStatus.session)
    public var questionStatuses: [QuestionStatus]

    @Relationship(deleteRule: .cascade, inverse: \TranscriptTurn.session)
    public var transcriptTurns: [TranscriptTurn]

    @Relationship(deleteRule: .cascade, inverse: \TranscriptGap.session)
    public var transcriptGaps: [TranscriptGap]

    @Relationship(deleteRule: .cascade, inverse: \AdHocNote.session)
    public var adHocNotes: [AdHocNote]

    @Relationship(deleteRule: .cascade, inverse: \ExportQueueEntry.session)
    public var exportQueueEntries: [ExportQueueEntry]

    public init(
        id: UUID = UUID(),
        guideSnapshot: GuideSnapshot,
        participantLabel: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        questionStatuses: [QuestionStatus] = [],
        transcriptTurns: [TranscriptTurn] = [],
        transcriptGaps: [TranscriptGap] = [],
        adHocNotes: [AdHocNote] = [],
        exportQueueEntries: [ExportQueueEntry] = []
    ) {
        self.id = id
        self.guideSnapshot = guideSnapshot
        self.participantLabel = participantLabel
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.questionStatuses = questionStatuses
        self.transcriptTurns = transcriptTurns
        self.transcriptGaps = transcriptGaps
        self.adHocNotes = adHocNotes
        self.exportQueueEntries = exportQueueEntries
    }
}

@Model
public final class TranscriptTurn {
    public var id: UUID
    public var speakerLabel: String
    public var text: String
    public var timestamp: Date
    public var isFinal: Bool
    public var session: Session?

    public init(
        id: UUID = UUID(),
        speakerLabel: String,
        text: String,
        timestamp: Date = .now,
        isFinal: Bool = true,
        session: Session? = nil
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.session = session
    }
}

@Model
public final class TranscriptGap {
    public var id: UUID
    public var sessionID: UUID
    public var startTimestamp: Date
    public var endTimestamp: Date
    public var reason: TranscriptGapReason
    public var session: Session?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        startTimestamp: Date,
        endTimestamp: Date,
        reason: TranscriptGapReason,
        session: Session? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.reason = reason
        self.session = session
    }
}

@Model
public final class QuestionStatus {
    public var id: UUID
    public var questionID: UUID
    public var status: QuestionCoverageStatus
    public var aiScore: Double?
    public var session: Session?

    public init(
        id: UUID = UUID(),
        questionID: UUID,
        status: QuestionCoverageStatus = .notStarted,
        aiScore: Double? = nil,
        session: Session? = nil
    ) {
        self.id = id
        self.questionID = questionID
        self.status = status
        self.aiScore = aiScore
        self.session = session
    }
}

@Model
public final class AdHocNote {
    public var id: UUID
    public var text: String
    public var timestamp: Date
    public var session: Session?

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = .now,
        session: Session? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.session = session
    }
}

@Model
public final class ExportQueueEntry {
    public var id: UUID
    public var sessionID: UUID
    public var queuedAt: Date
    public var attemptCount: Int
    public var lastAttemptAt: Date?
    public var session: Session?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        queuedAt: Date = .now,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        session: Session? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.queuedAt = queuedAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.session = session
    }
}
