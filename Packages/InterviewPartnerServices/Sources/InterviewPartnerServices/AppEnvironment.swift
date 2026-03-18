import SwiftData
import InterviewPartnerData
import InterviewPartnerDomain

@MainActor
public final class Sprint1AppEnvironment {
    public let modelContainer: ModelContainer
    public let guideRepository: any GuideRepository
    public let sessionRepository: any SessionRepository
    public let workspaceExporter: any WorkspaceExporter
    public let workspaceGuideImporter: any WorkspaceGuideImporter
    public let permissionManager: any PermissionManager
    public let keychainStore: any KeychainStore

    public init(inMemoryOnly: Bool = false) throws {
        let modelContainer = try InterviewPartnerModelContainer.make(inMemoryOnly: inMemoryOnly)
        let workspaceExporter = DefaultWorkspaceExporter()

        self.modelContainer = modelContainer
        self.workspaceExporter = workspaceExporter
        workspaceGuideImporter = DefaultWorkspaceGuideImporter()
        permissionManager = StubPermissionManager()
        keychainStore = StubKeychainStore()
        guideRepository = SwiftDataGuideRepository(
            modelContainer: modelContainer,
            workspaceExporter: workspaceExporter
        )
        sessionRepository = SwiftDataSessionRepository(modelContainer: modelContainer)
    }
}
