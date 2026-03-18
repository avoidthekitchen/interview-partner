import Foundation
import SwiftData
import InterviewPartnerDomain

@MainActor
public final class SwiftDataSessionRepository: SessionRepository {
    private let modelContainer: ModelContainer

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

    @discardableResult
    public func createSession(
        guideSnapshot: GuideSnapshot,
        participantLabel: String?
    ) throws -> UUID {
        let session = Session(
            guideSnapshot: guideSnapshot,
            participantLabel: participantLabel
        )
        modelContainer.mainContext.insert(session)
        try modelContainer.mainContext.save()
        return session.id
    }
}
