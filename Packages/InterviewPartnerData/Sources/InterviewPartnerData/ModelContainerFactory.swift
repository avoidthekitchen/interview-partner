import SwiftData

public enum InterviewPartnerModelContainer {
    @MainActor
    public static func make(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(InterviewPartnerSchema.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemoryOnly)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

public enum InterviewPartnerSchema {
    public static let models: [any PersistentModel.Type] = [
        Guide.self,
        Question.self,
        Session.self,
        TranscriptTurn.self,
        TranscriptGap.self,
        QuestionStatus.self,
        AdHocNote.self,
        ExportQueueEntry.self,
    ]
}
