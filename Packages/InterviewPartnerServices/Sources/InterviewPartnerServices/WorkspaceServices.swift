import Foundation
import InterviewPartnerDomain

@MainActor
public final class DefaultWorkspaceExporter: WorkspaceExporter {
    private enum Constants {
        static let bookmarkKey = "workspace.folder.bookmark"
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults

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

    @discardableResult
    public func exportSessionBundle(_ bundle: SessionExportBundle) throws -> [URL] {
        let folderName = sessionFolderName(
            startedAt: bundle.startedAt,
            sessionID: bundle.sessionID
        )
        let markdownURL = try write(
            data: Data(bundle.markdown.utf8),
            relativePath: "InterviewPartner/sessions/\(folderName)/transcript.md"
        )
        let jsonURL = try write(
            data: bundle.jsonData,
            relativePath: "InterviewPartner/sessions/\(folderName)/session.json"
        )
        let tempMarkdownURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(folderName)-transcript.md")
        let tempJSONURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(folderName)-session.json")

        try Data(bundle.markdown.utf8).write(to: tempMarkdownURL, options: .atomic)
        try bundle.jsonData.write(to: tempJSONURL, options: .atomic)
        return [markdownURL, jsonURL, tempMarkdownURL, tempJSONURL]
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
        return destinationURL
    }

    private func resolvedWorkspace() throws -> ResolvedWorkspace {
        let status = currentWorkspaceStatus()
        guard status.storageLocation == .securityScopedBookmark,
              let bookmarkData = userDefaults.data(forKey: Constants.bookmarkKey)
        else {
            return ResolvedWorkspace(baseURL: status.resolvedBaseURL, stopAccessing: {})
        }

        var isStale = false
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: bookmarkResolutionOptions,
            bookmarkDataIsStale: &isStale
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
