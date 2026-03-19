import Combine
import Observation
import OSLog
import SwiftUI
import InterviewPartnerDomain
import InterviewPartnerServices

@MainActor
@Observable
final class SessionCoordinator: Identifiable {
    let id: UUID

    @ObservationIgnored
    private let sessionRepository: any SessionRepository
    @ObservationIgnored
    private let workspaceExporter: any WorkspaceExporter
    @ObservationIgnored
    private let transcriptionService: any TranscriptionService
    @ObservationIgnored
    private let logger = Logger(
        subsystem: "com.mistercheese.InterviewPartner",
        category: "SessionCoordinator"
    )

    private var timerCancellable: AnyCancellable?
    private var didStart = false
    private var skipUndoResetTask: Task<Void, Never>?

    var guideSnapshot: GuideSnapshot
    var participantLabel: String?
    var startedAt: Date
    var endedAt: Date?
    var transcript: [TranscriptTurn]
    var gaps: [TranscriptGap]
    var partialTurn: String?
    var questionStatuses: [QuestionAnswerStatus]
    var adHocNotes: [AdHocNote]
    var elapsedSeconds: Int
    var diarizationAvailable = true
    var limitedModeMessage: String?
    var diarizationSnapshot: DiarizationSnapshot?
    var errorMessage: String?
    var nonBlockingErrorMessage: String?
    var isEnding = false
    var didFinishSession = false
    var skipUndoState: SkipUndoState?

    init(
        session: SessionRecord,
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter,
        transcriptionService: any TranscriptionService
    ) {
        id = session.id
        self.sessionRepository = sessionRepository
        self.workspaceExporter = workspaceExporter
        self.transcriptionService = transcriptionService
        guideSnapshot = session.guideSnapshot
        participantLabel = session.participantLabel
        startedAt = session.startedAt
        endedAt = session.endedAt
        transcript = session.transcriptTurns
        gaps = session.transcriptGaps
        partialTurn = nil
        questionStatuses = session.questionStatuses
        adHocNotes = session.adHocNotes
        elapsedSeconds = max(Int(Date.now.timeIntervalSince(session.startedAt)), 0)
    }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        transcriptionService.setEventHandler { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleTranscriptionEvent(event)
            }
        }

        startTimer()

        do {
            try await transcriptionService.start(sessionID: id, startedAt: startedAt)
        } catch {
            timerCancellable?.cancel()
            errorMessage = error.localizedDescription
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startTimer()
        case .background, .inactive:
            timerCancellable?.cancel()
        @unknown default:
            break
        }
    }

    func endSession() async {
        guard !isEnding else { return }
        isEnding = true
        timerCancellable?.cancel()

        let stopResult = await transcriptionService.stop()
        transcript = stopResult.reconciledTurns.sorted { $0.timestamp < $1.timestamp }
        diarizationSnapshot = stopResult.diarizationSnapshot
        diarizationAvailable = stopResult.diarizationAvailable
        limitedModeMessage = stopResult.limitedModeMessage
        partialTurn = nil
        endedAt = .now

        let finalizedRecord: SessionRecord
        do {
            finalizedRecord = try sessionRepository.finalizeSession(
                id: id,
                endedAt: endedAt ?? .now,
                reconciledTurns: transcript
            )
            applySessionRecord(finalizedRecord)
        } catch {
            errorMessage = error.localizedDescription
            isEnding = false
            return
        }

        do {
            let exportOutcome = try performSessionExport(
                session: finalizedRecord,
                sessionRepository: sessionRepository,
                workspaceExporter: workspaceExporter
            )
            applySessionRecord(exportOutcome.session)
        } catch {
            errorMessage = error.localizedDescription
        }

        didFinishSession = true
        isEnding = false
    }

    func cycleStatus(for questionID: UUID) {
        updateQuestionStatus(questionID: questionID, status: currentStatus(for: questionID).nextTapStatus)
    }

    func skipQuestion(_ questionID: UUID) {
        let previousStatus = currentStatus(for: questionID)
        updateQuestionStatus(questionID: questionID, status: .skipped)
        skipUndoState = SkipUndoState(questionID: questionID, previousStatus: previousStatus)
        scheduleSkipUndoReset()
    }

    func undoLastSkip() {
        guard let skipUndoState else { return }
        skipUndoResetTask?.cancel()
        updateQuestionStatus(
            questionID: skipUndoState.questionID,
            status: skipUndoState.previousStatus
        )
        self.skipUndoState = nil
    }

    func addAdHocNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let note = AdHocNote(text: trimmed, timestamp: .now)
        adHocNotes.append(note)
        persistIncrementalWrite(
            operation: "append ad hoc note"
        ) {
            try sessionRepository.appendAdHocNote(note, to: id)
        }
    }

    func status(for questionID: UUID) -> QuestionCoverageStatus {
        currentStatus(for: questionID)
    }

    func questions(for priority: QuestionPriority) -> [GuideSnapshotQuestion] {
        guideSnapshot.questions
            .filter { $0.priority == priority }
            .sorted { lhs, rhs in
                let lhsStatus = currentStatus(for: lhs.id)
                let rhsStatus = currentStatus(for: rhs.id)

                if lhsStatus.displayRank == rhsStatus.displayRank {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return lhsStatus.displayRank < rhsStatus.displayRank
            }
    }

    var headerTitle: String {
        participantLabel ?? guideSnapshot.name
    }

    var mustCoverProgressText: String {
        let mustCoverQuestions = guideSnapshot.questions.filter { $0.priority == .mustCover }
        let answered = mustCoverQuestions.filter { currentStatus(for: $0.id) == .answered }.count
        let elapsedMinutes = elapsedSeconds / 60
        return "\(answered) of \(mustCoverQuestions.count) Must Cover · \(elapsedMinutes)m elapsed"
    }

    var canShowLimitedModeBanner: Bool {
        limitedModeMessage != nil
    }

    private func startTimer() {
        timerCancellable?.cancel()
        refreshElapsedTime()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshElapsedTime()
            }
    }

    private func handleTranscriptionEvent(_ event: TranscriptionServiceEvent) {
        switch event {
        case .partialText(let text):
            partialTurn = text.isEmpty ? nil : text

        case .finalizedTurn(let turn):
            transcript.append(turn)
            persistIncrementalWrite(
                operation: "append transcript turn"
            ) {
                try sessionRepository.appendTranscriptTurn(turn, to: id)
            }

        case .transcriptGap(let gap):
            gaps.append(gap)
            persistIncrementalWrite(
                operation: "append transcript gap"
            ) {
                try sessionRepository.appendTranscriptGap(gap, to: id)
            }

        case .diarizationSnapshot(let snapshot):
            diarizationSnapshot = snapshot

        case .limitedModeChanged(let isLimited, let message):
            diarizationAvailable = !isLimited
            limitedModeMessage = message
        }
    }

    private func currentStatus(for questionID: UUID) -> QuestionCoverageStatus {
        questionStatuses.first(where: { $0.questionID == questionID })?.status ?? .notStarted
    }

    private func updateQuestionStatus(questionID: UUID, status: QuestionCoverageStatus) {
        let newStatus = QuestionAnswerStatus(
            id: questionStatuses.first(where: { $0.questionID == questionID })?.id ?? UUID(),
            questionID: questionID,
            status: status,
            aiScore: nil
        )

        if let index = questionStatuses.firstIndex(where: { $0.questionID == questionID }) {
            questionStatuses[index] = newStatus
        } else {
            questionStatuses.append(newStatus)
        }

        persistIncrementalWrite(
            operation: "update question status"
        ) {
            try sessionRepository.upsertQuestionStatus(newStatus, for: id)
        }
    }

    private func scheduleSkipUndoReset() {
        skipUndoResetTask?.cancel()
        let currentToken = skipUndoState?.id
        skipUndoResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, skipUndoState?.id == currentToken else { return }
            skipUndoState = nil
        }
    }

    private func applySessionRecord(_ record: SessionRecord) {
        guideSnapshot = record.guideSnapshot
        participantLabel = record.participantLabel
        startedAt = record.startedAt
        transcript = record.transcriptTurns
        gaps = record.transcriptGaps
        questionStatuses = record.questionStatuses
        adHocNotes = record.adHocNotes
        endedAt = record.endedAt
    }

    private func refreshElapsedTime() {
        elapsedSeconds = max(Int(Date.now.timeIntervalSince(startedAt)), 0)
    }

    private func persistIncrementalWrite(
        operation: String,
        _ write: () throws -> Void
    ) {
        do {
            try write()
            nonBlockingErrorMessage = nil
        } catch {
            handleIncrementalWriteFailure(error, operation: operation)
        }
    }

    private func handleIncrementalWriteFailure(_ error: Error, operation: String) {
        logger.error(
            "Non-fatal session persistence failure during \(operation, privacy: .public) for session \(self.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
        nonBlockingErrorMessage = "The latest session change could not be saved locally. Capture will continue, but review the session before relying on the export."
    }
}

struct SkipUndoState: Identifiable, Equatable {
    let id = UUID()
    let questionID: UUID
    let previousStatus: QuestionCoverageStatus
}

struct ActiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: SessionCoordinator
    @State private var panelState: ScriptPanelSnapState = .default
    @State private var showEndConfirmation = false
    @State private var showPanicSheet = false
    @State private var showNoteComposer = false
    @State private var noteDraft = ""

    init(coordinator: SessionCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                SessionHeaderView(
                    title: coordinator.headerTitle,
                    elapsedSeconds: coordinator.elapsedSeconds,
                    onPanicTap: { showPanicSheet = true },
                    onEndTap: { showEndConfirmation = true }
                )

                if let limitedModeMessage = coordinator.limitedModeMessage {
                    LimitedModeBanner(message: limitedModeMessage)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if let nonBlockingErrorMessage = coordinator.nonBlockingErrorMessage {
                    NonBlockingErrorBanner(message: nonBlockingErrorMessage)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                TranscriptView(
                    transcript: coordinator.transcript,
                    gaps: coordinator.gaps,
                    partialTurn: coordinator.partialTurn
                )
            }
            .safeAreaInset(edge: .bottom) {
                ScriptPanelView(
                    coordinator: coordinator,
                    panelState: $panelState,
                    showNoteComposer: $showNoteComposer,
                    onPanicTap: { showPanicSheet = true }
                )
                .frame(height: panelState.height(in: geometry.size.height))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 48, height: 5)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: panelState)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            panelState = panelState.nextState(for: value.translation.height)
                        }
                )
            }
            .overlay(alignment: .bottom) {
                if let skipUndoState = coordinator.skipUndoState {
                    UndoToast(
                        text: "Marked skipped",
                        onUndo: { coordinator.undoLastSkip() }
                    )
                    .padding(.bottom, panelState.height(in: geometry.size.height) + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(skipUndoState.id)
                }
            }
            .overlay(alignment: .bottom) {
                if showNoteComposer {
                    QuickNoteOverlay(
                        noteDraft: $noteDraft,
                        onCancel: {
                            noteDraft = ""
                            showNoteComposer = false
                        },
                        onSave: {
                            coordinator.addAdHocNote(noteDraft)
                            noteDraft = ""
                            showNoteComposer = false
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, panelState.height(in: geometry.size.height) + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showPanicSheet) {
                PanicQuestionListView(coordinator: coordinator)
            }
            .confirmationDialog(
                "End interview session?",
                isPresented: $showEndConfirmation,
                titleVisibility: .visible
            ) {
                Button("End Session", role: .destructive) {
                    Task { await coordinator.endSession() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This stops live transcription and finalizes the session in history.")
            }
            .alert(
                "Session Error",
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
            .task {
                await coordinator.startIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                coordinator.handleScenePhase(newPhase)
            }
            .onChange(of: coordinator.didFinishSession) { _, didFinish in
                if didFinish {
                    dismiss()
                }
            }
            .overlay {
                if coordinator.isEnding {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        ProgressView("Finalizing session...")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct SessionHeaderView: View {
    let title: String
    let elapsedSeconds: Int
    let onPanicTap: () -> Void
    let onEndTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.elapsedString(from: elapsedSeconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onPanicTap) {
                Image(systemName: "rectangle.grid.1x2")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Show full question list")

            Button("End", role: .destructive, action: onEndTap)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemBackground))
    }

    private static func elapsedString(from totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct TranscriptView: View {
    let transcript: [TranscriptTurn]
    let gaps: [TranscriptGap]
    let partialTurn: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcriptItems) { item in
                        switch item {
                        case .turn(let turn):
                            TranscriptTurnRow(turn: turn)
                                .id(turn.id)
                        case .gap(let gap):
                            TranscriptGapRow(gap: gap)
                                .id(gap.id)
                        }
                    }

                    if let partialTurn, !partialTurn.isEmpty {
                        PartialTurnRow(text: partialTurn)
                            .id("partial-turn")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .onChange(of: transcript.count) { _, _ in
                if let lastID = transcript.last?.id {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var transcriptItems: [TranscriptItem] {
        let visibleTurns = Array(transcript.suffix(50))
        let earliestVisibleDate = visibleTurns.first?.timestamp
        let visibleGaps = gaps.filter { gap in
            guard let earliestVisibleDate else { return true }
            return gap.endTimestamp >= earliestVisibleDate || gap.startTimestamp >= earliestVisibleDate
        }
        let turnItems = visibleTurns.map(TranscriptItem.turn)
        let gapItems = visibleGaps.map(TranscriptItem.gap)
        return (turnItems + gapItems).sorted { lhs, rhs in
            lhs.sortDate < rhs.sortDate
        }
    }
}

private enum TranscriptItem: Identifiable {
    case turn(TranscriptTurn)
    case gap(TranscriptGap)

    var id: AnyHashable {
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

private struct TranscriptTurnRow: View {
    let turn: TranscriptTurn

    var body: some View {
        HStack {
            if turn.speakerLabel == "Speaker B" {
                Spacer(minLength: 44)
            }

            VStack(alignment: turn.speakerLabel == "Speaker B" ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(turn.speakerLabel)
                        .font(.caption.weight(.semibold))
                    Text(turn.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(turn.text)
                    .foregroundStyle(.primary)

                if turn.speakerLabelIsProvisional {
                    Text(provisionalSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 320, alignment: turn.speakerLabel == "Speaker B" ? .trailing : .leading)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if turn.speakerLabel != "Speaker B" {
                Spacer(minLength: 44)
            }
        }
    }

    private var provisionalSummary: String {
        if let speakerMatchConfidence = turn.speakerMatchConfidence {
            return "Live label · \(Int((speakerMatchConfidence * 100).rounded()))% confidence"
        }
        return "Live label"
    }

    private var bubbleColor: Color {
        switch turn.speakerLabel {
        case "Speaker A":
            return Color.teal.opacity(0.18)
        case "Speaker B":
            return Color.orange.opacity(0.18)
        default:
            return Color.secondary.opacity(0.16)
        }
    }
}

private struct TranscriptGapRow: View {
    let gap: TranscriptGap

    var body: some View {
        Text("[transcription unavailable \(Self.timeString(gap.startTimestamp))-\(Self.timeString(gap.endTimestamp))]")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
    }

    private static func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct PartialTurnRow: View {
    let text: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Listening...")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 44)
        }
    }
}

private enum ScriptPanelSnapState: CaseIterable {
    case collapsed
    case `default`
    case expanded

    func height(in availableHeight: CGFloat) -> CGFloat {
        switch self {
        case .collapsed:
            return min(max(availableHeight * 0.20, 130), 180)
        case .default:
            return min(max(availableHeight * 0.42, 280), 380)
        case .expanded:
            return min(max(availableHeight * 0.72, 460), availableHeight - 32)
        }
    }

    func nextState(for translation: CGFloat) -> ScriptPanelSnapState {
        if translation < -80 {
            switch self {
            case .collapsed: return .default
            case .default: return .expanded
            case .expanded: return .expanded
            }
        }

        if translation > 80 {
            switch self {
            case .expanded: return .default
            case .default: return .collapsed
            case .collapsed: return .collapsed
            }
        }

        return self
    }
}

private struct ScriptPanelView: View {
    @Bindable var coordinator: SessionCoordinator
    @Binding var panelState: ScriptPanelSnapState
    @Binding var showNoteComposer: Bool
    let onPanicTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Script")
                        .font(.headline)
                    Text(coordinator.mustCoverProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showNoteComposer = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add ad hoc note")

                Button(action: onPanicTap) {
                    Image(systemName: "rectangle.grid.1x2")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Show all questions")
            }
            .padding(.top, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(QuestionPriority.allCases) { priority in
                        let questions = coordinator.questions(for: priority)
                        if !questions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(priority.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(questions) { question in
                                    ScriptQuestionRow(
                                        question: question,
                                        status: coordinator.status(for: question.id),
                                        onTap: { coordinator.cycleStatus(for: question.id) },
                                        onLongPress: { coordinator.skipQuestion(question.id) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }

            HStack {
                Button(panelState == .expanded ? "Collapse" : "Expand") {
                    panelState = panelState == .expanded ? .default : .expanded
                }
                .font(.footnote.weight(.medium))

                Spacer()

                Text("\(coordinator.adHocNotes.count) note\(coordinator.adHocNotes.count == 1 ? "" : "s")")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

private struct ScriptQuestionRow: View {
    let question: GuideSnapshotQuestion
    let status: QuestionCoverageStatus
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.text)
                        .strikethrough(status == .skipped, color: .secondary)
                        .foregroundStyle(status == .answered ? .secondary : .primary)
                        .multilineTextAlignment(.leading)

                    if !question.subPrompts.isEmpty {
                        Text(question.subPrompts.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                StatusBadge(status: status)
            }
            .padding(12)
            .background(statusBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .onLongPressGesture(perform: onLongPress)
    }

    private var statusBackground: Color {
        switch status {
        case .answered:
            return Color.green.opacity(0.10)
        case .partial:
            return Color.yellow.opacity(0.14)
        case .skipped:
            return Color.secondary.opacity(0.10)
        case .notStarted:
            return Color.secondary.opacity(0.08)
        }
    }
}

private struct StatusBadge: View {
    let status: QuestionCoverageStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch status {
        case .answered:
            return .green
        case .partial:
            return .orange
        case .skipped:
            return .secondary
        case .notStarted:
            return .blue
        }
    }
}

private struct PanicQuestionListView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: SessionCoordinator

    var body: some View {
        NavigationStack {
            List {
                ForEach(QuestionPriority.allCases) { priority in
                    let questions = coordinator.questions(for: priority)
                    if !questions.isEmpty {
                        Section(priority.title) {
                            ForEach(questions) { question in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(question.text)
                                    Spacer(minLength: 8)
                                    StatusBadge(status: coordinator.status(for: question.id))
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.cycleStatus(for: question.id)
                                }
                                .onLongPressGesture {
                                    coordinator.skipQuestion(question.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("All Questions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct UndoToast: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.footnote)
            Spacer(minLength: 12)
            Button("Undo", action: onUndo)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 24)
    }
}

private struct QuickNoteOverlay: View {
    @Binding var noteDraft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick note")
                    .font(.headline)
                Spacer()
                Text(Date.now.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField("Capture a note without leaving the session", text: $noteDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }
}

private struct LimitedModeBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NonBlockingErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension QuestionCoverageStatus {
    var nextTapStatus: QuestionCoverageStatus {
        switch self {
        case .notStarted:
            return .partial
        case .partial:
            return .answered
        case .answered, .skipped:
            return .notStarted
        }
    }

    var displayRank: Int {
        switch self {
        case .notStarted:
            return 0
        case .partial:
            return 1
        case .answered:
            return 2
        case .skipped:
            return 3
        }
    }
}
