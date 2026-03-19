import Observation
import SwiftUI
import InterviewPartnerDomain
import InterviewPartnerServices

@MainActor
@Observable
final class SessionSetupCoordinator: Identifiable {
    let id = UUID()

    @ObservationIgnored
    private let guideRepository: any GuideRepository
    @ObservationIgnored
    private let sessionRepository: any SessionRepository
    @ObservationIgnored
    private let permissionManager: any PermissionManager
    @ObservationIgnored
    private let makeTranscriptionService: @MainActor () -> any TranscriptionService

    var guides: [GuideSummary] = []
    var selectedGuideID: UUID?
    var participantLabel = ""
    var errorMessage: String?
    var isStarting = false

    init(
        guideRepository: any GuideRepository,
        sessionRepository: any SessionRepository,
        permissionManager: any PermissionManager,
        makeTranscriptionService: @escaping @MainActor () -> any TranscriptionService
    ) {
        self.guideRepository = guideRepository
        self.sessionRepository = sessionRepository
        self.permissionManager = permissionManager
        self.makeTranscriptionService = makeTranscriptionService
    }

    func load() {
        do {
            guides = try guideRepository.fetchGuides()
            selectedGuideID = selectedGuideID ?? guides.first?.id
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startInterview() async -> SessionCoordinator? {
        guard let selectedGuideID else {
            errorMessage = "Choose a guide before starting the interview."
            return nil
        }

        isStarting = true
        defer { isStarting = false }

        let permissionState: MicrophonePermissionState
        switch permissionManager.microphonePermissionState() {
        case .granted:
            permissionState = .granted
        case .notDetermined:
            permissionState = await permissionManager.requestMicrophonePermission()
        case .denied:
            permissionState = .denied
        }

        guard permissionState == .granted else {
            errorMessage = "Microphone access is required to run a live interview session."
            return nil
        }

        do {
            guard let guideDraft = try guideRepository.fetchGuide(id: selectedGuideID) else {
                errorMessage = "That guide could not be loaded."
                return nil
            }

            let session = try sessionRepository.createSession(
                guideSnapshot: guideDraft.snapshot,
                participantLabel: participantLabel.normalizedNilIfEmpty
            )

            errorMessage = nil
            return SessionCoordinator(
                session: session,
                sessionRepository: sessionRepository,
                transcriptionService: makeTranscriptionService()
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

@MainActor
@Observable
final class SessionListCoordinator {
    @ObservationIgnored
    private let guideRepository: any GuideRepository
    @ObservationIgnored
    private let sessionRepository: any SessionRepository
    @ObservationIgnored
    fileprivate let workspaceExporter: any WorkspaceExporter
    @ObservationIgnored
    private let permissionManager: any PermissionManager
    @ObservationIgnored
    private let makeTranscriptionService: @MainActor () -> any TranscriptionService

    var sessions: [SessionSummary] = []
    var workspaceStatus: WorkspaceStatus
    var errorMessage: String?
    var showWorkspaceSetup = false
    var showMissingGuideAlert = false
    var sessionSetup: SessionSetupCoordinator?
    var activeSession: SessionCoordinator?

    init(
        guideRepository: any GuideRepository,
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter,
        permissionManager: any PermissionManager,
        makeTranscriptionService: @escaping @MainActor () -> any TranscriptionService
    ) {
        self.guideRepository = guideRepository
        self.sessionRepository = sessionRepository
        self.workspaceExporter = workspaceExporter
        self.permissionManager = permissionManager
        self.makeTranscriptionService = makeTranscriptionService
        workspaceStatus = workspaceExporter.currentWorkspaceStatus()
    }

    func load() {
        workspaceStatus = workspaceExporter.currentWorkspaceStatus()

        do {
            sessions = try sessionRepository.fetchSessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleNewSessionTap() {
        workspaceStatus = workspaceExporter.currentWorkspaceStatus()

        if workspaceStatus.requiresSetupForNewSession {
            showWorkspaceSetup = true
            return
        }

        do {
            let guides = try guideRepository.fetchGuides()
            guard !guides.isEmpty else {
                showMissingGuideAlert = true
                return
            }

            let setup = SessionSetupCoordinator(
                guideRepository: guideRepository,
                sessionRepository: sessionRepository,
                permissionManager: permissionManager,
                makeTranscriptionService: makeTranscriptionService
            )
            setup.guides = guides
            setup.selectedGuideID = guides.first?.id
            sessionSetup = setup
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct SessionListView: View {
    @State private var coordinator: SessionListCoordinator
    private let workspaceRefreshToken: UUID

    public init(
        guideRepository: any GuideRepository,
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter,
        permissionManager: any PermissionManager,
        makeTranscriptionService: @escaping @MainActor () -> any TranscriptionService,
        workspaceRefreshToken: UUID
    ) {
        _coordinator = State(
            initialValue: SessionListCoordinator(
                guideRepository: guideRepository,
                sessionRepository: sessionRepository,
                workspaceExporter: workspaceExporter,
                permissionManager: permissionManager,
                makeTranscriptionService: makeTranscriptionService
            )
        )
        self.workspaceRefreshToken = workspaceRefreshToken
    }

    public var body: some View {
        @Bindable var bindable = coordinator

        Group {
            if coordinator.sessions.isEmpty {
                VStack(spacing: 20) {
                    if let warningMessage = coordinator.workspaceStatus.warningMessage {
                        warningBanner(message: warningMessage)
                    }

                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Pick a guide, add an optional participant label, and start a live interview session.")
                    )

                    Button("New Session") {
                        coordinator.handleNewSessionTap()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    if let warningMessage = coordinator.workspaceStatus.warningMessage {
                        Section {
                            warningBanner(message: warningMessage)
                                .listRowInsets(EdgeInsets())
                        }
                    }

                    Section("Past Sessions") {
                        ForEach(coordinator.sessions) { session in
                            SessionRowView(session: session)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Session") {
                    coordinator.handleNewSessionTap()
                }
            }
        }
        .task {
            coordinator.load()
        }
        .onChange(of: workspaceRefreshToken) { _, _ in
            coordinator.load()
        }
        .sheet(isPresented: $bindable.showWorkspaceSetup) {
            WorkspaceSetupSheet(
                workspaceExporter: coordinator.workspaceExporter,
                onWorkspaceUpdated: {
                    coordinator.load()
                }
            )
        }
        .sheet(item: $bindable.sessionSetup) { setup in
            SessionSetupSheet(
                coordinator: setup,
                onCancel: {
                    coordinator.sessionSetup = nil
                },
                onStart: { activeSession in
                    coordinator.activeSession = activeSession
                    coordinator.sessionSetup = nil
                }
            )
        }
        .fullScreenCover(item: $bindable.activeSession, onDismiss: {
            coordinator.load()
        }) { activeSession in
            ActiveSessionView(coordinator: activeSession)
        }
        .alert("Create A Guide First", isPresented: $bindable.showMissingGuideAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sprint 2 sessions require a saved guide. Create one in the Guides tab before starting an interview.")
        }
        .alert(
            "Session List Error",
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

    private func warningBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SessionSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: SessionSetupCoordinator
    let onCancel: () -> Void
    let onStart: (SessionCoordinator) -> Void

    init(
        coordinator: SessionSetupCoordinator,
        onCancel: @escaping () -> Void,
        onStart: @escaping (SessionCoordinator) -> Void
    ) {
        _coordinator = State(initialValue: coordinator)
        self.onCancel = onCancel
        self.onStart = onStart
    }

    var body: some View {
        @Bindable var bindable = coordinator

        NavigationStack {
            Form {
                Section("Guide") {
                    Picker("Interview Guide", selection: $bindable.selectedGuideID) {
                        ForEach(coordinator.guides) { guide in
                            Text(guide.name).tag(Optional(guide.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Participant") {
                    TextField("Optional participant label", text: $bindable.participantLabel)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if coordinator.isStarting {
                        ProgressView()
                    } else {
                        Button("Start Interview") {
                            Task {
                                if let activeSession = await coordinator.startInterview() {
                                    onStart(activeSession)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .task {
                coordinator.load()
            }
            .alert(
                "Session Setup Error",
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
}

private struct SessionRowView: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.participantLabel ?? session.guideName)
                .font(.headline)
            Text(session.guideName)
                .foregroundStyle(.secondary)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("Must Cover: \(session.answeredMustCoverCount)/\(session.mustCoverQuestionCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let endedAt = session.endedAt {
                    Spacer(minLength: 12)
                    Text(Self.durationText(start: session.startedAt, end: endedAt))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static func durationText(start: Date, end: Date) -> String {
        let totalSeconds = max(Int(end.timeIntervalSince(start)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02dm %02ds", minutes, seconds)
    }
}

private extension String {
    var normalizedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
