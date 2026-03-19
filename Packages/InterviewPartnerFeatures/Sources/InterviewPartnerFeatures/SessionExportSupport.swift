import Foundation
import InterviewPartnerDomain
import InterviewPartnerServices

struct SessionExportOutcome {
    let session: SessionRecord
    let result: SessionExportResult
}

@MainActor
func performSessionExport(
    session: SessionRecord,
    sessionRepository: any SessionRepository,
    workspaceExporter: any WorkspaceExporter
) throws -> SessionExportOutcome {
    let bundle = SessionExportBundle(
        sessionID: session.id,
        startedAt: session.startedAt,
        markdown: workspaceExporter.generateTranscriptMarkdown(session: session),
        jsonData: try workspaceExporter.generateSessionJSON(session: session)
    )

    if session.hasPendingExport {
        try sessionRepository.recordExportAttempt(for: session.id, at: .now)
    }

    let result = try workspaceExporter.exportSessionBundle(bundle)
    let updatedSession: SessionRecord

    if result.workspaceWriteSucceeded, session.hasPendingExport {
        updatedSession = try sessionRepository.markExportCompleted(for: session.id)
    } else {
        updatedSession = try sessionRepository.fetchSession(id: session.id) ?? session
    }

    return SessionExportOutcome(session: updatedSession, result: result)
}

func sessionListWarningMessage(
    workspaceStatus: WorkspaceStatus,
    pendingExportCount: Int
) -> String? {
    guard let warningMessage = workspaceStatus.warningMessage else { return nil }

    guard pendingExportCount > 0 else {
        return warningMessage
    }

    let noun = pendingExportCount == 1 ? "export is" : "exports are"
    return "\(warningMessage) \(pendingExportCount) pending \(noun) waiting to retry."
}
