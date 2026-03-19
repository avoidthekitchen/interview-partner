import Foundation

public enum QuestionPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case mustCover = "must_cover"
    case shouldCover = "should_cover"
    case niceToHave = "nice_to_have"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .mustCover:
            "Must Cover"
        case .shouldCover:
            "Should Cover"
        case .niceToHave:
            "Nice to Have"
        }
    }
}

public struct GuideQuestionDraft: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var priority: QuestionPriority
    public var orderIndex: Int
    public var subPrompts: [String]

    public init(
        id: UUID = UUID(),
        text: String = "",
        priority: QuestionPriority = .mustCover,
        orderIndex: Int = 0,
        subPrompts: [String] = []
    ) {
        self.id = id
        self.text = text
        self.priority = priority
        self.orderIndex = orderIndex
        self.subPrompts = subPrompts
    }
}

public struct GuideDraft: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var goal: String
    public var createdAt: Date
    public var questions: [GuideQuestionDraft]

    public init(
        id: UUID = UUID(),
        name: String = "",
        goal: String = "",
        createdAt: Date = .now,
        questions: [GuideQuestionDraft] = []
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.createdAt = createdAt
        self.questions = questions
    }

    public static var empty: GuideDraft {
        GuideDraft(
            questions: [
                GuideQuestionDraft(orderIndex: 0),
            ]
        )
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedQuestions: [GuideQuestionDraft] {
        questions
            .enumerated()
            .map { index, question in
                GuideQuestionDraft(
                    id: question.id,
                    text: question.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    priority: question.priority,
                    orderIndex: index,
                    subPrompts: question.subPrompts
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
            .filter { !$0.text.isEmpty }
    }

    public var snapshot: GuideSnapshot {
        GuideSnapshot(
            id: id,
            name: trimmedName,
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            questions: normalizedQuestions.map {
                GuideSnapshotQuestion(
                    id: $0.id,
                    text: $0.text,
                    priority: $0.priority,
                    orderIndex: $0.orderIndex,
                    subPrompts: $0.subPrompts
                )
            }
        )
    }

    public var exportDocument: GuideExportDocument {
        GuideExportDocument(
            id: id,
            name: trimmedName,
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            questions: normalizedQuestions.map {
                GuideExportQuestion(
                    id: $0.id,
                    text: $0.text,
                    priority: $0.priority,
                    orderIndex: $0.orderIndex,
                    subPrompts: $0.subPrompts
                )
            },
            branch: nil,
            aiScoringPromptOverride: nil
        )
    }

    public func duplicated() -> GuideDraft {
        GuideDraft(
            name: trimmedName.isEmpty ? "Untitled Guide Copy" : "\(trimmedName) Copy",
            goal: goal,
            questions: normalizedQuestions.enumerated().map { index, question in
                GuideQuestionDraft(
                    text: question.text,
                    priority: question.priority,
                    orderIndex: index,
                    subPrompts: question.subPrompts
                )
            }
        )
    }
}

public struct GuideSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var goal: String
    public var createdAt: Date
    public var questionCount: Int

    public init(
        id: UUID,
        name: String,
        goal: String,
        createdAt: Date,
        questionCount: Int
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.createdAt = createdAt
        self.questionCount = questionCount
    }
}

public struct GuideSnapshotQuestion: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var priority: QuestionPriority
    public var orderIndex: Int
    public var subPrompts: [String]

    public init(
        id: UUID,
        text: String,
        priority: QuestionPriority,
        orderIndex: Int,
        subPrompts: [String]
    ) {
        self.id = id
        self.text = text
        self.priority = priority
        self.orderIndex = orderIndex
        self.subPrompts = subPrompts
    }
}

public struct GuideSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var goal: String
    public var createdAt: Date
    public var questions: [GuideSnapshotQuestion]

    public init(
        id: UUID,
        name: String,
        goal: String,
        createdAt: Date,
        questions: [GuideSnapshotQuestion]
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.createdAt = createdAt
        self.questions = questions
    }
}

public struct GuideExportQuestion: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var priority: QuestionPriority
    public var orderIndex: Int
    public var subPrompts: [String]

    public init(
        id: UUID,
        text: String,
        priority: QuestionPriority,
        orderIndex: Int,
        subPrompts: [String]
    ) {
        self.id = id
        self.text = text
        self.priority = priority
        self.orderIndex = orderIndex
        self.subPrompts = subPrompts
    }
}

public struct GuideExportDocument: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var goal: String
    public var createdAt: Date
    public var questions: [GuideExportQuestion]
    public var branch: String?
    public var aiScoringPromptOverride: String?

    public init(
        id: UUID,
        name: String,
        goal: String,
        createdAt: Date,
        questions: [GuideExportQuestion],
        branch: String?,
        aiScoringPromptOverride: String?
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.createdAt = createdAt
        self.questions = questions
        self.branch = branch
        self.aiScoringPromptOverride = aiScoringPromptOverride
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case goal
        case createdAt = "created_at"
        case questions
        case branch
        case aiScoringPromptOverride = "ai_scoring_prompt_override"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(goal, forKey: .goal)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(questions, forKey: .questions)

        if let branch {
            try container.encode(branch, forKey: .branch)
        } else {
            try container.encodeNil(forKey: .branch)
        }

        if let aiScoringPromptOverride {
            try container.encode(aiScoringPromptOverride, forKey: .aiScoringPromptOverride)
        } else {
            try container.encodeNil(forKey: .aiScoringPromptOverride)
        }
    }
}

public struct WorkspaceStatus: Equatable, Sendable {
    public enum StorageLocation: String, Codable, Sendable {
        case securityScopedBookmark
        case documentsFallback
    }

    public var storageLocation: StorageLocation
    public var iCloudDriveAvailable: Bool
    public var hasBookmark: Bool
    public var selectedFolderName: String?
    public var resolvedBaseURL: URL
    public var warningMessage: String?

    public init(
        storageLocation: StorageLocation,
        iCloudDriveAvailable: Bool,
        hasBookmark: Bool,
        selectedFolderName: String?,
        resolvedBaseURL: URL,
        warningMessage: String?
    ) {
        self.storageLocation = storageLocation
        self.iCloudDriveAvailable = iCloudDriveAvailable
        self.hasBookmark = hasBookmark
        self.selectedFolderName = selectedFolderName
        self.resolvedBaseURL = resolvedBaseURL
        self.warningMessage = warningMessage
    }

    public var requiresSetupForNewSession: Bool {
        !hasBookmark && iCloudDriveAvailable
    }

    public var storageDescription: String {
        switch storageLocation {
        case .securityScopedBookmark:
            selectedFolderName ?? resolvedBaseURL.lastPathComponent
        case .documentsFallback:
            "App Documents"
        }
    }
}

public extension String {
    func interviewPartnerSlug() -> String {
        let lowercase = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = lowercase.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }

            return "-"
        }

        let raw = String(allowed)
        let collapsed = raw.replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "guide" : trimmed
    }
}
