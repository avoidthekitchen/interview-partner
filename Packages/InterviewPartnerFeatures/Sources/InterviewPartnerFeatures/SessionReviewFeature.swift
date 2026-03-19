import Observation
import OSLog
import SwiftUI
import UIKit
import InterviewPartnerDomain
import InterviewPartnerServices

@MainActor
@Observable
final class ReviewCoordinator {
    @ObservationIgnored
    private let sessionRepository: any SessionRepository
    @ObservationIgnored
    private let workspaceExporter: any WorkspaceExporter
    @ObservationIgnored
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "ReviewCoordinator"
    )

    let sessionID: UUID

    var session: SessionRecord?
    var errorMessage: String?
    var exportStatusMessage: String?
    var shareSheetURLs: [URL] = []

    init(
        sessionID: UUID,
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter
    ) {
        self.sessionID = sessionID
        self.sessionRepository = sessionRepository
        self.workspaceExporter = workspaceExporter
    }

    func load() {
        do {
            guard let session = try sessionRepository.fetchSession(id: sessionID) else {
                logger.error(
                    "Failed to load session \(self.sessionID.uuidString, privacy: .public): session not found"
                )
                errorMessage = "That session could not be loaded."
                return
            }

            self.session = session
            logger.info(
                "Loaded review for session \(session.id.uuidString, privacy: .public). Turns: \(session.transcriptTurns.count, privacy: .public), gaps: \(session.transcriptGaps.count, privacy: .public), pending export: \(session.hasPendingExport, privacy: .public)"
            )
            errorMessage = nil
        } catch {
            logger.error(
                "Failed to load session \(self.sessionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    func updateTurnText(turnID: UUID, text: String) {
        guard var session else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            logger.error(
                "Rejected empty transcript edit for session \(session.id.uuidString, privacy: .public), turn \(turnID.uuidString, privacy: .public)"
            )
            errorMessage = "Transcript text cannot be empty."
            return
        }
        guard let index = session.transcriptTurns.firstIndex(where: { $0.id == turnID }) else { return }

        session.transcriptTurns[index].text = trimmedText

        do {
            logger.info(
                "Saving transcript edit for session \(session.id.uuidString, privacy: .public), turn \(turnID.uuidString, privacy: .public)"
            )
            let updatedSession = try sessionRepository.updateTranscriptTurn(
                session.transcriptTurns[index],
                in: session.id
            )
            self.session = updatedSession
            errorMessage = nil
        } catch {
            logger.error(
                "Failed transcript edit for session \(session.id.uuidString, privacy: .public), turn \(turnID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    func renameSpeakerLabel(from originalLabel: String, to newLabel: String) {
        guard let session else { return }

        do {
            logger.info(
                "Renaming speaker label in session \(session.id.uuidString, privacy: .public) from \(originalLabel, privacy: .public) to \(newLabel, privacy: .public)"
            )
            self.session = try sessionRepository.renameSpeakerLabel(
                in: session.id,
                from: originalLabel,
                to: newLabel
            )
            errorMessage = nil
        } catch {
            logger.error(
                "Failed speaker rename in session \(session.id.uuidString, privacy: .public) from \(originalLabel, privacy: .public) to \(newLabel, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    func exportForSharing() {
        guard let session else { return }

        do {
            logger.info(
                "Starting share/export flow for session \(session.id.uuidString, privacy: .public)"
            )
            let exportOutcome = try performSessionExport(
                session: session,
                sessionRepository: sessionRepository,
                workspaceExporter: workspaceExporter
            )
            self.session = exportOutcome.session
            shareSheetURLs = exportOutcome.result.temporaryFileURLs
            exportStatusMessage = exportOutcome.result.workspaceWriteSucceeded
                ? "Workspace export is up to date."
                : "Temporary export files are ready. Workspace export is still pending retry."
            logger.info(
                "Share/export flow finished for session \(session.id.uuidString, privacy: .public). Workspace success: \(exportOutcome.result.workspaceWriteSucceeded, privacy: .public), temporary URLs: \(self.shareSheetURLs.count, privacy: .public)"
            )
            errorMessage = nil
        } catch {
            logger.error(
                "Share/export flow failed for session \(session.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }

    var title: String {
        session?.participantLabel ?? session?.guideSnapshot.name ?? "Session Review"
    }

    var previewMarkdown: String {
        guard let session else { return "" }
        return workspaceExporter.generateTranscriptMarkdown(session: session)
    }

    var transcriptItems: [ReviewTranscriptItem] {
        guard let session else { return [] }

        let turns = session.transcriptTurns.map(ReviewTranscriptItem.turn)
        let gaps = session.transcriptGaps.map(ReviewTranscriptItem.gap)
        return (turns + gaps).sorted { $0.sortDate < $1.sortDate }
    }

    func questions(for priority: QuestionPriority) -> [GuideSnapshotQuestion] {
        guard let session else { return [] }
        return session.guideSnapshot.questions
            .filter { $0.priority == priority }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    func status(for questionID: UUID) -> QuestionCoverageStatus {
        guard let session else { return .notStarted }
        return session.questionStatuses.first(where: { $0.questionID == questionID })?.status ?? .notStarted
    }
}

enum ReviewTab: String, CaseIterable, Identifiable {
    case transcript = "Transcript"
    case coverage = "Coverage"
    case export = "Export"

    var id: Self { self }
}

enum ReviewTranscriptItem: Identifiable {
    case turn(TranscriptTurn)
    case gap(TranscriptGap)

    var id: UUID {
        switch self {
        case .turn(let turn):
            return turn.id
        case .gap(let gap):
            return gap.id
        }
    }

    var sortDate: Date {
        switch self {
        case .turn(let turn):
            return turn.timestamp
        case .gap(let gap):
            return gap.startTimestamp
        }
    }
}

struct SessionReviewContainerView: View {
    @State private var coordinator: ReviewCoordinator

    init(
        sessionID: UUID,
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter
    ) {
        _coordinator = State(
            initialValue: ReviewCoordinator(
                sessionID: sessionID,
                sessionRepository: sessionRepository,
                workspaceExporter: workspaceExporter
            )
        )
    }

    var body: some View {
        SessionReviewView(coordinator: coordinator)
            .task {
                coordinator.load()
            }
            .alert(
                "Review Error",
                isPresented: Binding(
                    get: { coordinator.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            coordinator.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.errorMessage ?? "Unknown error")
            }
    }
}

private struct SessionReviewView: View {
    @Bindable var coordinator: ReviewCoordinator
    @State private var selectedTab: ReviewTab = .transcript
    @State private var editingTurn: TranscriptTurn?
    @State private var editedText = ""
    @State private var renameSourceLabel: String?
    @State private var renamedLabel = ""
    @State private var showShareSheet = false

    var body: some View {
        Group {
            if coordinator.session == nil {
                ContentUnavailableView(
                    "Loading Session",
                    systemImage: "waveform.path.ecg",
                    description: Text("Fetching transcript, coverage, and export data.")
                )
            } else {
                VStack(spacing: 16) {
                    Picker("Review Section", selection: $selectedTab) {
                        ForEach(ReviewTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .transcript:
                        TranscriptReviewTab(
                            items: coordinator.transcriptItems,
                            onEditTurn: { turn in
                                editingTurn = turn
                                editedText = turn.text
                            },
                            onRenameSpeaker: { label in
                                renameSourceLabel = label
                                renamedLabel = label
                            }
                        )
                    case .coverage:
                        CoverageReviewTab(coordinator: coordinator)
                    case .export:
                        ExportReviewTab(
                            previewMarkdown: coordinator.previewMarkdown,
                            hasPendingExport: coordinator.session?.hasPendingExport == true,
                            exportStatusMessage: coordinator.exportStatusMessage,
                            onShare: {
                                coordinator.exportForSharing()
                                showShareSheet = !coordinator.shareSheetURLs.isEmpty
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle(coordinator.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTurn) { turn in
            NavigationStack {
                TranscriptTurnEditorSheet(
                    title: turn.speakerLabel,
                    text: $editedText,
                    onCancel: {
                        editingTurn = nil
                    },
                    onSave: {
                        coordinator.updateTurnText(turnID: turn.id, text: editedText)
                        editingTurn = nil
                    }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: coordinator.shareSheetURLs.map { $0 as Any })
        }
        .alert(
            "Rename Speaker",
            isPresented: Binding(
                get: { renameSourceLabel != nil },
                set: { isPresented in
                    if !isPresented {
                        renameSourceLabel = nil
                    }
                }
            )
        ) {
            TextField("Speaker name", text: $renamedLabel)
            Button("Cancel", role: .cancel) {
                renameSourceLabel = nil
            }
            Button("Save") {
                if let renameSourceLabel {
                    coordinator.renameSpeakerLabel(from: renameSourceLabel, to: renamedLabel)
                }
                renameSourceLabel = nil
            }
        } message: {
            Text("This updates every transcript turn with the same label in this session.")
        }
    }
}

private struct TranscriptReviewTab: View {
    let items: [ReviewTranscriptItem]
    let onEditTurn: (TranscriptTurn) -> Void
    let onRenameSpeaker: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    switch item {
                    case .turn(let turn):
                        TranscriptReviewTurnCard(
                            turn: turn,
                            onEdit: { onEditTurn(turn) },
                            onRenameSpeaker: { onRenameSpeaker(turn.speakerLabel) }
                        )
                    case .gap(let gap):
                        TranscriptReviewGapCard(gap: gap)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TranscriptReviewTurnCard: View {
    let turn: TranscriptTurn
    let onEdit: () -> Void
    let onRenameSpeaker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onRenameSpeaker) {
                    Text(turn.speakerLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                Text(turn.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Button(action: onEdit) {
                Text(turn.text)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let confidence = turn.speakerMatchConfidence {
                Text("Live attribution confidence: \(Int((confidence * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TranscriptReviewGapCard: View {
    let gap: TranscriptGap

    var body: some View {
        Text("[transcription unavailable \(gap.startTimestamp.formatted(date: .omitted, time: .shortened))-\(gap.endTimestamp.formatted(date: .omitted, time: .shortened))]")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CoverageReviewTab: View {
    @Bindable var coordinator: ReviewCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(QuestionPriority.allCases) { priority in
                    let questions = coordinator.questions(for: priority)
                    if !questions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(priority.title)
                                .font(.headline)

                            ForEach(questions) { question in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(question.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(coordinator.status(for: question.id).title)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.14), in: Capsule())
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Ad Hoc Notes")
                        .font(.headline)

                    if let session = coordinator.session, !session.adHocNotes.isEmpty {
                        ForEach(session.adHocNotes) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(note.text)
                            }
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    } else {
                        Text("No ad hoc notes were captured.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ExportReviewTab: View {
    let previewMarkdown: String
    let hasPendingExport: Bool
    let exportStatusMessage: String?
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("Share Files", action: onShare)
                    .buttonStyle(.borderedProminent)

                if hasPendingExport {
                    Text("Pending workspace retry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if let exportStatusMessage {
                Text(exportStatusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(previewMarkdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct TranscriptTurnEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextEditor(text: $text)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave()
                    dismiss()
                }
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
