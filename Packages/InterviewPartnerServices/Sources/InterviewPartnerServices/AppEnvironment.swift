import SwiftData
import InterviewPartnerData
import InterviewPartnerDomain

@MainActor
public final class AppEnvironment {
    public let modelContainer: ModelContainer
    public let guideRepository: any GuideRepository
    public let sessionRepository: any SessionRepository
    public let workspaceExporter: any WorkspaceExporter
    public let workspaceGuideImporter: any WorkspaceGuideImporter
    public let permissionManager: any PermissionManager
    public let keychainStore: any KeychainStore
    public let makeTranscriptionService: @MainActor () -> any TranscriptionService

    public init(inMemoryOnly: Bool = false) throws {
        let modelContainer = try InterviewPartnerModelContainer.make(inMemoryOnly: inMemoryOnly)
        let workspaceExporter = DefaultWorkspaceExporter()

        self.modelContainer = modelContainer
        self.workspaceExporter = workspaceExporter
        workspaceGuideImporter = DefaultWorkspaceGuideImporter()
        permissionManager = SystemPermissionManager()
        keychainStore = StubKeychainStore()
        makeTranscriptionService = { DefaultTranscriptionService() }
        guideRepository = SwiftDataGuideRepository(
            modelContainer: modelContainer,
            workspaceExporter: workspaceExporter
        )
        sessionRepository = SwiftDataSessionRepository(modelContainer: modelContainer)
    }
}

public typealias Sprint1AppEnvironment = AppEnvironment
