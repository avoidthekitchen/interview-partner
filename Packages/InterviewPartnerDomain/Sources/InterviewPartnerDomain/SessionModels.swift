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
    public var startTimeSeconds: TimeInterval?
    public var endTimeSeconds: TimeInterval?
    public var speakerMatchConfidence: Double?
    public var speakerLabelIsProvisional: Bool

    public init(
        id: UUID = UUID(),
        speakerLabel: String = "Speaker A",
        text: String,
        timestamp: Date = .now,
        isFinal: Bool = true,
        startTimeSeconds: TimeInterval? = nil,
        endTimeSeconds: TimeInterval? = nil,
        speakerMatchConfidence: Double? = nil,
        speakerLabelIsProvisional: Bool = false
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.speakerMatchConfidence = speakerMatchConfidence
        self.speakerLabelIsProvisional = speakerLabelIsProvisional
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

public struct SessionRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var guideSnapshot: GuideSnapshot
    public var participantLabel: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var transcriptTurns: [TranscriptTurn]
    public var transcriptGaps: [TranscriptGap]
    public var questionStatuses: [QuestionAnswerStatus]
    public var adHocNotes: [AdHocNote]
    public var hasPendingExport: Bool

    public init(
        id: UUID,
        guideSnapshot: GuideSnapshot,
        participantLabel: String?,
        startedAt: Date,
        endedAt: Date?,
        transcriptTurns: [TranscriptTurn],
        transcriptGaps: [TranscriptGap],
        questionStatuses: [QuestionAnswerStatus],
        adHocNotes: [AdHocNote],
        hasPendingExport: Bool
    ) {
        self.id = id
        self.guideSnapshot = guideSnapshot
        self.participantLabel = participantLabel
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcriptTurns = transcriptTurns
        self.transcriptGaps = transcriptGaps
        self.questionStatuses = questionStatuses
        self.adHocNotes = adHocNotes
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

public struct SessionExportResult: Hashable, Sendable {
    public var temporaryFileURLs: [URL]
    public var workspaceFileURLs: [URL]
    public var workspaceWriteSucceeded: Bool
    public var workspaceErrorDescription: String?

    public init(
        temporaryFileURLs: [URL],
        workspaceFileURLs: [URL],
        workspaceWriteSucceeded: Bool,
        workspaceErrorDescription: String?
    ) {
        self.temporaryFileURLs = temporaryFileURLs
        self.workspaceFileURLs = workspaceFileURLs
        self.workspaceWriteSucceeded = workspaceWriteSucceeded
        self.workspaceErrorDescription = workspaceErrorDescription
    }
}

public struct SessionExportDocument: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var guide: GuideSnapshot
    public var participantLabel: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var transcriptTurns: [SessionExportTurn]
    public var transcriptGaps: [SessionExportGap]
    public var questionStatuses: [SessionExportQuestionStatus]
    public var adHocNotes: [AdHocNote]
    public var branch: String?
    public var aiScoringPromptOverride: String?

    public init(
        id: UUID,
        guide: GuideSnapshot,
        participantLabel: String?,
        startedAt: Date,
        endedAt: Date?,
        transcriptTurns: [SessionExportTurn],
        transcriptGaps: [SessionExportGap],
        questionStatuses: [SessionExportQuestionStatus],
        adHocNotes: [AdHocNote],
        branch: String?,
        aiScoringPromptOverride: String?
    ) {
        self.id = id
        self.guide = guide
        self.participantLabel = participantLabel
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcriptTurns = transcriptTurns
        self.transcriptGaps = transcriptGaps
        self.questionStatuses = questionStatuses
        self.adHocNotes = adHocNotes
        self.branch = branch
        self.aiScoringPromptOverride = aiScoringPromptOverride
    }
}

public struct SessionExportTurn: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var reconciledSpeakerLabel: String
    public var text: String
    public var timestamp: Date
    public var isFinal: Bool
    public var startTimeSeconds: TimeInterval?
    public var endTimeSeconds: TimeInterval?
    public var liveSpeakerMatchConfidence: Double?

    public init(
        id: UUID,
        reconciledSpeakerLabel: String,
        text: String,
        timestamp: Date,
        isFinal: Bool,
        startTimeSeconds: TimeInterval?,
        endTimeSeconds: TimeInterval?,
        liveSpeakerMatchConfidence: Double?
    ) {
        self.id = id
        self.reconciledSpeakerLabel = reconciledSpeakerLabel
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.liveSpeakerMatchConfidence = liveSpeakerMatchConfidence
    }
}

public struct SessionExportGap: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startTimestamp: Date
    public var endTimestamp: Date
    public var reason: TranscriptGapReason

    public init(
        id: UUID,
        startTimestamp: Date,
        endTimestamp: Date,
        reason: TranscriptGapReason
    ) {
        self.id = id
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.reason = reason
    }
}

public struct SessionExportQuestionStatus: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var questionID: UUID
    public var questionText: String
    public var priority: QuestionPriority
    public var orderIndex: Int
    public var status: QuestionCoverageStatus
    public var aiScore: Double?

    public init(
        id: UUID = UUID(),
        questionID: UUID,
        questionText: String,
        priority: QuestionPriority,
        orderIndex: Int,
        status: QuestionCoverageStatus,
        aiScore: Double?
    ) {
        self.id = id
        self.questionID = questionID
        self.questionText = questionText
        self.priority = priority
        self.orderIndex = orderIndex
        self.status = status
        self.aiScore = aiScore
    }
}

public enum MicrophonePermissionState: String, Codable, Sendable {
    case notDetermined
    case granted
    case denied
}
