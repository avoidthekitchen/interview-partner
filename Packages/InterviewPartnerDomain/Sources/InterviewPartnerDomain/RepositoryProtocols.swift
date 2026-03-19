import Foundation

@MainActor
public protocol GuideRepository: AnyObject {
    func fetchGuides() throws -> [GuideSummary]
    func fetchGuide(id: UUID) throws -> GuideDraft?
    @discardableResult
    func saveGuide(_ draft: GuideDraft) throws -> GuideSummary
    func deleteGuide(id: UUID) throws
    @discardableResult
    func duplicateGuide(id: UUID) throws -> GuideSummary
}

@MainActor
public protocol SessionRepository: AnyObject {
    func fetchSessions() throws -> [SessionSummary]
    func fetchSession(id: UUID) throws -> SessionRecord?
    func fetchPendingExportSessions() throws -> [SessionRecord]
    @discardableResult
    func createSession(
        guideSnapshot: GuideSnapshot,
        participantLabel: String?
    ) throws -> SessionRecord
    func appendTranscriptTurn(_ turn: TranscriptTurn, to sessionID: UUID) throws
    func appendTranscriptGap(_ gap: TranscriptGap, to sessionID: UUID) throws
    func upsertQuestionStatus(_ status: QuestionAnswerStatus, for sessionID: UUID) throws
    func appendAdHocNote(_ note: AdHocNote, to sessionID: UUID) throws
    @discardableResult
    func updateTranscriptTurn(_ turn: TranscriptTurn, in sessionID: UUID) throws -> SessionRecord
    @discardableResult
    func renameSpeakerLabel(
        in sessionID: UUID,
        from originalLabel: String,
        to newLabel: String
    ) throws -> SessionRecord
    func finalizeSession(
        id: UUID,
        endedAt: Date,
        reconciledTurns: [TranscriptTurn]
    ) throws -> SessionRecord
    func recordExportAttempt(for sessionID: UUID, at attemptedAt: Date) throws
    @discardableResult
    func markExportCompleted(for sessionID: UUID) throws -> SessionRecord
}

@MainActor
public protocol WorkspaceExporter: AnyObject {
    func currentWorkspaceStatus() -> WorkspaceStatus
    @discardableResult
    func saveWorkspaceBookmark(for folderURL: URL) throws -> WorkspaceStatus
    @discardableResult
    func exportGuide(_ guide: GuideExportDocument) throws -> URL
    func generateTranscriptMarkdown(session: SessionRecord) -> String
    func generateSessionJSON(session: SessionRecord) throws -> Data
    @discardableResult
    func exportSessionBundle(_ bundle: SessionExportBundle) throws -> SessionExportResult
}

@MainActor
public protocol WorkspaceGuideImporter: AnyObject {
    func importGuides() throws -> [GuideDraft]
}

@MainActor
public protocol PermissionManager: AnyObject {
    func microphonePermissionState() -> MicrophonePermissionState
    func requestMicrophonePermission() async -> MicrophonePermissionState
}

@MainActor
public protocol KeychainStore: AnyObject {
    func string(forKey key: String) throws -> String?
    func setString(_ value: String, forKey key: String) throws
    func removeValue(forKey key: String) throws
}
