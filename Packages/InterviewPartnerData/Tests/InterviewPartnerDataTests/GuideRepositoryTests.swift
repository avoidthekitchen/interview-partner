import Foundation
import SwiftData
import Testing
import InterviewPartnerDomain
@testable import InterviewPartnerData

@MainActor
private final class MockWorkspaceExporter: WorkspaceExporter {
    var status: WorkspaceStatus
    var lastExportedGuide: GuideExportDocument?

    init() {
        status = WorkspaceStatus(
            storageLocation: .documentsFallback,
            iCloudDriveAvailable: false,
            hasBookmark: false,
            selectedFolderName: nil,
            resolvedBaseURL: URL(fileURLWithPath: NSTemporaryDirectory()),
            warningMessage: nil
        )
    }

    func currentWorkspaceStatus() -> WorkspaceStatus {
        status
    }

    func saveWorkspaceBookmark(for folderURL: URL) throws -> WorkspaceStatus {
        status = WorkspaceStatus(
            storageLocation: .securityScopedBookmark,
            iCloudDriveAvailable: true,
            hasBookmark: true,
            selectedFolderName: folderURL.lastPathComponent,
            resolvedBaseURL: folderURL,
            warningMessage: nil
        )
        return status
    }

    func exportGuide(_ guide: GuideExportDocument) throws -> URL {
        lastExportedGuide = guide
        return status.resolvedBaseURL.appendingPathComponent("\(guide.name).json")
    }

    func exportSessionBundle(_ bundle: SessionExportBundle) throws -> [URL] {
        []
    }
}

@MainActor
@Test func saveGuidePersistsQuestionsAndExportsDocument() throws {
    let container = try InterviewPartnerModelContainer.make(inMemoryOnly: true)
    let exporter = MockWorkspaceExporter()
    let repository = SwiftDataGuideRepository(
        modelContainer: container,
        workspaceExporter: exporter
    )

    let summary = try repository.saveGuide(
        GuideDraft(
            name: "Behavioral Screen",
            goal: "Evaluate leadership and execution.",
            questions: [
                GuideQuestionDraft(
                    text: "Tell me about a launch you led.",
                    priority: .mustCover,
                    orderIndex: 0,
                    subPrompts: ["How did you measure success?"]
                ),
                GuideQuestionDraft(
                    text: "What would you do differently?",
                    priority: .shouldCover,
                    orderIndex: 1
                ),
            ]
        )
    )

    let reloaded = try repository.fetchGuide(id: summary.id)

    #expect(summary.questionCount == 2)
    #expect(reloaded?.questions.count == 2)
    #expect(exporter.lastExportedGuide?.branch == nil)
    #expect(exporter.lastExportedGuide?.aiScoringPromptOverride == nil)
}

@MainActor
@Test func duplicateGuideClonesQuestionsWithFreshIdentity() throws {
    let container = try InterviewPartnerModelContainer.make(inMemoryOnly: true)
    let exporter = MockWorkspaceExporter()
    let repository = SwiftDataGuideRepository(
        modelContainer: container,
        workspaceExporter: exporter
    )

    let original = try repository.saveGuide(
        GuideDraft(
            name: "Manager Loop",
            goal: "Stress test operating cadence.",
            questions: [
                GuideQuestionDraft(
                    text: "Walk me through a roadmap reset.",
                    priority: .mustCover,
                    orderIndex: 0
                ),
            ]
        )
    )

    let duplicate = try repository.duplicateGuide(id: original.id)
    let guides = try repository.fetchGuides()

    #expect(guides.count == 2)
    #expect(duplicate.id != original.id)
    #expect(duplicate.name.contains("Copy"))
}
