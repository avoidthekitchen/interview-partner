import Foundation
import SwiftData
import InterviewPartnerDomain

public enum GuideRepositoryError: LocalizedError {
    case guideNotFound
    case guideNameRequired
    case atLeastOneQuestionRequired

    public var errorDescription: String? {
        switch self {
        case .guideNotFound:
            "The selected guide no longer exists."
        case .guideNameRequired:
            "Give the guide a name before saving."
        case .atLeastOneQuestionRequired:
            "Add at least one non-empty question before saving."
        }
    }
}

@MainActor
public final class SwiftDataGuideRepository: GuideRepository {
    private let modelContainer: ModelContainer
    private let workspaceExporter: any WorkspaceExporter

    public init(
        modelContainer: ModelContainer,
        workspaceExporter: any WorkspaceExporter
    ) {
        self.modelContainer = modelContainer
        self.workspaceExporter = workspaceExporter
    }

    public func fetchGuides() throws -> [GuideSummary] {
        let descriptor = FetchDescriptor<Guide>(
            sortBy: [SortDescriptor(\Guide.createdAt, order: .reverse)]
        )

        return try modelContainer.mainContext.fetch(descriptor).map(Self.summary(from:))
    }

    public func fetchGuide(id: UUID) throws -> GuideDraft? {
        try fetchGuideModel(id: id).map(Self.draft(from:))
    }

    @discardableResult
    public func saveGuide(_ draft: GuideDraft) throws -> GuideSummary {
        let trimmedName = draft.trimmedName
        guard !trimmedName.isEmpty else {
            throw GuideRepositoryError.guideNameRequired
        }

        let normalizedQuestions = draft.normalizedQuestions
        guard !normalizedQuestions.isEmpty else {
            throw GuideRepositoryError.atLeastOneQuestionRequired
        }

        let guideModel = try fetchGuideModel(id: draft.id) ?? {
            let guide = Guide(
                id: draft.id,
                name: trimmedName,
                goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: draft.createdAt
            )
            modelContainer.mainContext.insert(guide)
            return guide
        }()

        guideModel.name = trimmedName
        guideModel.goal = draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)

        var existingQuestionsByID = Dictionary(
            uniqueKeysWithValues: guideModel.questions.map { ($0.id, $0) }
        )
        var reorderedQuestions: [Question] = []

        for (index, questionDraft) in normalizedQuestions.enumerated() {
            let questionModel = existingQuestionsByID.removeValue(forKey: questionDraft.id) ?? {
                let question = Question(
                    id: questionDraft.id,
                    text: questionDraft.text,
                    priority: questionDraft.priority,
                    orderIndex: index,
                    subPrompts: questionDraft.subPrompts,
                    guide: guideModel
                )
                modelContainer.mainContext.insert(question)
                return question
            }()

            questionModel.text = questionDraft.text
            questionModel.priority = questionDraft.priority
            questionModel.orderIndex = index
            questionModel.subPrompts = questionDraft.subPrompts
            questionModel.guide = guideModel
            reorderedQuestions.append(questionModel)
        }

        for orphan in existingQuestionsByID.values {
            modelContainer.mainContext.delete(orphan)
        }

        guideModel.questions = reorderedQuestions

        try modelContainer.mainContext.save()
        _ = try workspaceExporter.exportGuide(Self.draft(from: guideModel).exportDocument)
        return Self.summary(from: guideModel)
    }

    public func deleteGuide(id: UUID) throws {
        guard let guide = try fetchGuideModel(id: id) else {
            return
        }

        modelContainer.mainContext.delete(guide)
        try modelContainer.mainContext.save()
    }

    @discardableResult
    public func duplicateGuide(id: UUID) throws -> GuideSummary {
        guard let guide = try fetchGuide(id: id) else {
            throw GuideRepositoryError.guideNotFound
        }

        return try saveGuide(guide.duplicated())
    }

    private func fetchGuideModel(id: UUID) throws -> Guide? {
        var descriptor = FetchDescriptor<Guide>(
            predicate: #Predicate<Guide> { guide in
                guide.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContainer.mainContext.fetch(descriptor).first
    }

    private static func summary(from guide: Guide) -> GuideSummary {
        GuideSummary(
            id: guide.id,
            name: guide.name,
            goal: guide.goal,
            createdAt: guide.createdAt,
            questionCount: guide.questions.count
        )
    }

    private static func draft(from guide: Guide) -> GuideDraft {
        GuideDraft(
            id: guide.id,
            name: guide.name,
            goal: guide.goal,
            createdAt: guide.createdAt,
            questions: guide.questions
                .sorted { $0.orderIndex < $1.orderIndex }
                .map {
                    GuideQuestionDraft(
                        id: $0.id,
                        text: $0.text,
                        priority: $0.priority,
                        orderIndex: $0.orderIndex,
                        subPrompts: $0.subPrompts
                    )
                }
        )
    }
}
