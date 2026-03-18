import Foundation

public enum QuestionCoverageStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case notStarted = "not_started"
    case partial
    case answered
    case skipped

    public var id: Self { self }

    public var title: String {
        switch self {
        case .notStarted:
            "Not Started"
        case .partial:
            "Partial"
        case .answered:
            "Answered"
        case .skipped:
            "Skipped"
        }
    }
}

public enum TranscriptGapReason: String, Codable, CaseIterable, Sendable {
    case transcriptionUnavailable = "transcription_unavailable"
    case recordingInterrupted = "recording_interrupted"
    case unknown
}

public struct TranscriptTurn: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var speakerLabel: String
    public var text: String
    public var timestamp: Date
    public var isFinal: Bool

    public init(
        id: UUID = UUID(),
        speakerLabel: String = "Speaker A",
        text: String,
        timestamp: Date = .now,
        isFinal: Bool = true
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
    }
}

public struct TranscriptGap: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var startTimestamp: Date
    public var endTimestamp: Date
    public var reason: TranscriptGapReason

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        startTimestamp: Date,
        endTimestamp: Date,
        reason: TranscriptGapReason
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.reason = reason
    }
}

public struct QuestionAnswerStatus: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var questionID: UUID
    public var status: QuestionCoverageStatus
    public var aiScore: Double?

    public init(
        id: UUID = UUID(),
        questionID: UUID,
        status: QuestionCoverageStatus = .notStarted,
        aiScore: Double? = nil
    ) {
        self.id = id
        self.questionID = questionID
        self.status = status
        self.aiScore = aiScore
    }
}

public struct AdHocNote: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

public struct SessionSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var guideName: String
    public var participantLabel: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var mustCoverQuestionCount: Int
    public var answeredMustCoverCount: Int
    public var hasPendingExport: Bool

    public init(
        id: UUID,
        guideName: String,
        participantLabel: String?,
        startedAt: Date,
        endedAt: Date?,
        mustCoverQuestionCount: Int,
        answeredMustCoverCount: Int,
        hasPendingExport: Bool
    ) {
        self.id = id
        self.guideName = guideName
        self.participantLabel = participantLabel
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mustCoverQuestionCount = mustCoverQuestionCount
        self.answeredMustCoverCount = answeredMustCoverCount
        self.hasPendingExport = hasPendingExport
    }
}

public struct SessionExportBundle: Hashable, Sendable {
    public var sessionID: UUID
    public var startedAt: Date
    public var markdown: String
    public var jsonData: Data

    public init(
        sessionID: UUID,
        startedAt: Date,
        markdown: String,
        jsonData: Data
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.markdown = markdown
        self.jsonData = jsonData
    }
}

public enum MicrophonePermissionState: String, Codable, Sendable {
    case notDetermined
    case granted
    case denied
}
