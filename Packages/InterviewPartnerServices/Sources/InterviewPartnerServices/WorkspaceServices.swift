import Foundation
import InterviewPartnerDomain
import OSLog

@MainActor
public final class DefaultWorkspaceExporter: WorkspaceExporter {
    private enum Constants {
        static let bookmarkKey = "workspace.folder.bookmark"
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "WorkspaceExporter"
    )

    public init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
    }

    public func currentWorkspaceStatus() -> WorkspaceStatus {
        let documentsURL = documentsDirectory()
        let iCloudDriveAvailable = fileManager.url(forUbiquityContainerIdentifier: nil) != nil

        guard let bookmarkData = userDefaults.data(forKey: Constants.bookmarkKey) else {
            logger.info(
                "No workspace bookmark found. Falling back to documents directory."
            )
            return WorkspaceStatus(
                storageLocation: .documentsFallback,
                iCloudDriveAvailable: iCloudDriveAvailable,
                hasBookmark: false,
                selectedFolderName: nil,
                resolvedBaseURL: documentsURL,
                warningMessage: iCloudDriveAvailable
                    ? "Pick an iCloud Drive folder before starting a session. Until then, exports fall back to the app documents directory."
                    : "iCloud Drive is unavailable. Exports fall back to the app documents directory."
            )
        }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: bookmarkResolutionOptions,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                logger.info("Workspace bookmark was stale. Refreshing bookmark data.")
                let refreshedBookmark = try resolvedURL.bookmarkData(
                    options: bookmarkCreationOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                userDefaults.set(refreshedBookmark, forKey: Constants.bookmarkKey)
            }

            return WorkspaceStatus(
                storageLocation: .securityScopedBookmark,
                iCloudDriveAvailable: iCloudDriveAvailable,
                hasBookmark: true,
                selectedFolderName: resolvedURL.lastPathComponent,
                resolvedBaseURL: resolvedURL,
                warningMessage: nil
            )
        } catch {
            logger.error(
                "Failed to resolve workspace bookmark: \(error.localizedDescription, privacy: .public)"
            )
            return WorkspaceStatus(
                storageLocation: .documentsFallback,
                iCloudDriveAvailable: iCloudDriveAvailable,
                hasBookmark: false,
                selectedFolderName: nil,
                resolvedBaseURL: documentsURL,
                warningMessage: "The saved workspace bookmark could not be reopened. Exports fall back to the app documents directory until you pick the folder again."
            )
        }
    }

    @discardableResult
    public func saveWorkspaceBookmark(for folderURL: URL) throws -> WorkspaceStatus {
        let bookmarkData = try folderURL.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        userDefaults.set(bookmarkData, forKey: Constants.bookmarkKey)
        logger.info(
            "Saved workspace bookmark for folder \(folderURL.lastPathComponent, privacy: .public)"
        )
        return currentWorkspaceStatus()
    }

    @discardableResult
    public func exportGuide(_ guide: GuideExportDocument) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(guide)
        let relativePath = "InterviewPartner/guides/\(guide.name.interviewPartnerSlug()).json"
        return try write(data: data, relativePath: relativePath)
    }

    public func generateTranscriptMarkdown(session: SessionRecord) -> String {
        logger.debug(
            "Generating transcript markdown for session \(session.id.uuidString, privacy: .public). Turns: \(session.transcriptTurns.count, privacy: .public), gaps: \(session.transcriptGaps.count, privacy: .public), notes: \(session.adHocNotes.count, privacy: .public)"
        )
        let transcriptBody = transcriptLines(for: session).joined(separator: "\n")
        let noteLines = session.adHocNotes.map { note in
            "- [\(transcriptTimeFormatter.string(from: note.timestamp))] \(note.text)"
        }
        let coverageSummaryLines = QuestionPriority.allCases.flatMap { priority in
            coverageLines(for: session, priority: priority)
        }

        let title = session.participantLabel ?? session.guideSnapshot.name
        let sessionDate = headerDateFormatter.string(from: session.startedAt)
        let startTime = headerTimeFormatter.string(from: session.startedAt)
        let endTime = session.endedAt.map { headerTimeFormatter.string(from: $0) } ?? "In progress"

        return [
            "# \(title)",
            "",
            "- Guide: \(session.guideSnapshot.name)",
            "- Date: \(sessionDate)",
            "- Started: \(startTime)",
            "- Ended: \(endTime)",
            "",
            "## Transcript",
            transcriptBody.isEmpty ? "_No transcript captured._" : transcriptBody,
            "",
            "## Ad Hoc Notes",
            noteLines.isEmpty ? "_No ad hoc notes._" : noteLines.joined(separator: "\n"),
            "",
            "## Coverage Summary",
            coverageSummaryLines.isEmpty ? "_No guide questions._" : coverageSummaryLines.joined(separator: "\n"),
        ].joined(separator: "\n")
    }

    public func generateSessionJSON(session: SessionRecord) throws -> Data {
        logger.debug(
            "Generating session JSON for session \(session.id.uuidString, privacy: .public)"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let document = SessionExportDocument(
            id: session.id,
            guide: session.guideSnapshot,
            participantLabel: session.participantLabel,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            transcriptTurns: session.transcriptTurns
                .sorted { $0.timestamp < $1.timestamp }
                .map {
                    SessionExportTurn(
                        id: $0.id,
                        reconciledSpeakerLabel: normalizedSpeakerLabel($0.speakerLabel),
                        text: $0.text,
                        timestamp: $0.timestamp,
                        isFinal: $0.isFinal,
                        startTimeSeconds: $0.startTimeSeconds,
                        endTimeSeconds: $0.endTimeSeconds,
                        liveSpeakerMatchConfidence: $0.speakerMatchConfidence
                    )
                },
            transcriptGaps: session.transcriptGaps
                .sorted { $0.startTimestamp < $1.startTimestamp }
                .map {
                    SessionExportGap(
                        id: $0.id,
                        startTimestamp: $0.startTimestamp,
                        endTimestamp: $0.endTimestamp,
                        reason: $0.reason
                    )
                },
            questionStatuses: session.guideSnapshot.questions
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { question in
                    SessionExportQuestionStatus(
                        questionID: question.id,
                        questionText: question.text,
                        priority: question.priority,
                        orderIndex: question.orderIndex,
                        status: status(for: question.id, in: session),
                        aiScore: session.questionStatuses.first(where: { $0.questionID == question.id })?.aiScore
                    )
                },
            adHocNotes: session.adHocNotes.sorted { $0.timestamp < $1.timestamp },
            branch: nil,
            aiScoringPromptOverride: nil
        )

        return try encoder.encode(document)
    }

    @discardableResult
    public func exportSessionBundle(_ bundle: SessionExportBundle) throws -> SessionExportResult {
        let folderName = sessionFolderName(
            startedAt: bundle.startedAt,
            sessionID: bundle.sessionID
        )
        let tempMarkdownURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(folderName)-transcript.md")
        let tempJSONURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(folderName)-session.json")

        try Data(bundle.markdown.utf8).write(to: tempMarkdownURL, options: .atomic)
        try bundle.jsonData.write(to: tempJSONURL, options: .atomic)
        logger.info(
            "Wrote temporary export files for session \(bundle.sessionID.uuidString, privacy: .public) to \(tempMarkdownURL.lastPathComponent, privacy: .public) and \(tempJSONURL.lastPathComponent, privacy: .public)"
        )

        do {
            let markdownURL = try write(
                data: Data(bundle.markdown.utf8),
                relativePath: "InterviewPartner/sessions/\(folderName)/transcript.md"
            )
            let jsonURL = try write(
                data: bundle.jsonData,
                relativePath: "InterviewPartner/sessions/\(folderName)/session.json"
            )
            logger.info(
                "Wrote workspace export files for session \(bundle.sessionID.uuidString, privacy: .public) to \(markdownURL.path(percentEncoded: false), privacy: .public) and \(jsonURL.path(percentEncoded: false), privacy: .public)"
            )

            return SessionExportResult(
                temporaryFileURLs: [tempMarkdownURL, tempJSONURL],
                workspaceFileURLs: [markdownURL, jsonURL],
                workspaceWriteSucceeded: true,
                workspaceErrorDescription: nil
            )
        } catch {
            logger.error(
                "Workspace export write failed for session \(bundle.sessionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return SessionExportResult(
                temporaryFileURLs: [tempMarkdownURL, tempJSONURL],
                workspaceFileURLs: [],
                workspaceWriteSucceeded: false,
                workspaceErrorDescription: error.localizedDescription
            )
        }
    }

    private func write(data: Data, relativePath: String) throws -> URL {
        let workspace = try resolvedWorkspace()
        defer { workspace.stopAccessing() }

        let destinationURL = workspace.baseURL.appendingPathComponent(relativePath)
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
        logger.debug(
            "Wrote file at relative path \(relativePath, privacy: .public)"
        )
        return destinationURL
    }

    private func resolvedWorkspace() throws -> ResolvedWorkspace {
        let status = currentWorkspaceStatus()
        guard status.storageLocation == .securityScopedBookmark,
              let bookmarkData = userDefaults.data(forKey: Constants.bookmarkKey)
        else {
            logger.info(
                "Using non-bookmark workspace destination at \(status.resolvedBaseURL.path(percentEncoded: false), privacy: .public)"
            )
            return ResolvedWorkspace(baseURL: status.resolvedBaseURL, stopAccessing: {})
        }

        var isStale = false
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            bookmarkDataIsStale: &isStale
        )
        logger.debug(
            "Resolved security-scoped workspace at \(folderURL.path(percentEncoded: false), privacy: .public)"
        )
        let isAccessing = folderURL.startAccessingSecurityScopedResource()
        let stopAccessing = {
            if isAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        return ResolvedWorkspace(
            baseURL: folderURL,
            stopAccessing: stopAccessing
        )
    }

    private func documentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private func sessionFolderName(startedAt: Date, sessionID: UUID) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: startedAt))-\(sessionID.uuidString.lowercased())"
    }

    private func transcriptLines(for session: SessionRecord) -> [String] {
        let turnLines = session.transcriptTurns.map { turn in
            MarkdownLine(
                sortDate: turn.timestamp,
                text: "[\(transcriptTimeFormatter.string(from: turn.timestamp))] \(normalizedSpeakerLabel(turn.speakerLabel)): \(turn.text)"
            )
        }
        let gapLines = session.transcriptGaps.map { gap in
            MarkdownLine(
                sortDate: gap.startTimestamp,
                text: "[transcription unavailable \(transcriptTimeFormatter.string(from: gap.startTimestamp))-\(transcriptTimeFormatter.string(from: gap.endTimestamp))]"
            )
        }

        return (turnLines + gapLines)
            .sorted { $0.sortDate < $1.sortDate }
            .map(\.text)
    }

    private func coverageLines(for session: SessionRecord, priority: QuestionPriority) -> [String] {
        let questions = session.guideSnapshot.questions
            .filter { $0.priority == priority }
            .sorted { $0.orderIndex < $1.orderIndex }

        guard !questions.isEmpty else { return [] }

        var lines = ["### \(priority.title)"]
        lines.append(contentsOf: questions.map { question in
            let status = status(for: question.id, in: session).title
            return "- [\(status)] \(question.text)"
        })
        return lines
    }

    private func status(for questionID: UUID, in session: SessionRecord) -> QuestionCoverageStatus {
        session.questionStatuses.first(where: { $0.questionID == questionID })?.status ?? .notStarted
    }

    private func normalizedSpeakerLabel(_ label: String) -> String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.isEmpty ? "Unclear" : trimmedLabel
    }

    private var headerDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }

    private var headerTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private var transcriptTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }
}

private struct ResolvedWorkspace {
    let baseURL: URL
    let stopAccessing: () -> Void
}

private struct MarkdownLine {
    let sortDate: Date
    let text: String
}
