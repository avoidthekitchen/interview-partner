import Foundation
import InterviewPartnerDomain
import InterviewPartnerServices
import OSLog

struct SessionExportOutcome {
    let session: SessionRecord
    let result: SessionExportResult
}

private let sessionExportLogger = Logger(
    subsystem: "com.mistercheese.InterviewPartner",
    category: "SessionExport"
)

@MainActor
func performSessionExport(
    session: SessionRecord,
    sessionRepository: any SessionRepository,
    workspaceExporter: any WorkspaceExporter
) throws -> SessionExportOutcome {
    sessionExportLogger.info(
        "Starting export for session \(session.id.uuidString, privacy: .public). Pending export before run: \(session.hasPendingExport, privacy: .public)"
    )

    let bundle = SessionExportBundle(
        sessionID: session.id,
        startedAt: session.startedAt,
        markdown: workspaceExporter.generateTranscriptMarkdown(session: session),
        jsonData: try workspaceExporter.generateSessionJSON(session: session)
    )

    if session.hasPendingExport {
        sessionExportLogger.debug(
            "Recording retry attempt for session \(session.id.uuidString, privacy: .public)"
        )
        try sessionRepository.recordExportAttempt(for: session.id, at: .now)
    }

    let result = try workspaceExporter.exportSessionBundle(bundle)
    let updatedSession: SessionRecord

    if result.workspaceWriteSucceeded, session.hasPendingExport {
        sessionExportLogger.info(
            "Workspace export succeeded for session \(session.id.uuidString, privacy: .public). Clearing pending export queue entry."
        )
        updatedSession = try sessionRepository.markExportCompleted(for: session.id)
    } else {
        if result.workspaceWriteSucceeded {
            sessionExportLogger.info(
                "Initial workspace export succeeded for session \(session.id.uuidString, privacy: .public)"
            )
        } else {
            sessionExportLogger.error(
                "Workspace export failed for session \(session.id.uuidString, privacy: .public): \(result.workspaceErrorDescription ?? "unknown error", privacy: .public)"
            )
        }
        updatedSession = try sessionRepository.fetchSession(id: session.id) ?? session
    }

    sessionExportLogger.info(
        "Export finished for session \(session.id.uuidString, privacy: .public). Temporary files: \(result.temporaryFileURLs.count, privacy: .public), workspace files: \(result.workspaceFileURLs.count, privacy: .public), pending export after run: \(updatedSession.hasPendingExport, privacy: .public)"
    )

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
