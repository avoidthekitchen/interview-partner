import Observation
import SwiftUI
import InterviewPartnerDomain

@MainActor
@Observable
final class SessionListCoordinator {
    @ObservationIgnored
    private let sessionRepository: any SessionRepository
    @ObservationIgnored
    fileprivate let workspaceExporter: any WorkspaceExporter

    var sessions: [SessionSummary] = []
    var workspaceStatus: WorkspaceStatus
    var errorMessage: String?
    var showWorkspaceSetup = false
    var showSprintTwoAlert = false

    init(
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter
    ) {
        self.sessionRepository = sessionRepository
        self.workspaceExporter = workspaceExporter
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

        showSprintTwoAlert = true
    }
}

public struct SessionListView: View {
    @State private var coordinator: SessionListCoordinator
    private let workspaceRefreshToken: UUID

    public init(
        sessionRepository: any SessionRepository,
        workspaceExporter: any WorkspaceExporter,
        workspaceRefreshToken: UUID
    ) {
        _coordinator = State(
            initialValue: SessionListCoordinator(
                sessionRepository: sessionRepository,
                workspaceExporter: workspaceExporter
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
                        systemImage: "mic.slash",
                        description: Text("Sprint 1 establishes the session shell and workspace gate. Session setup and active interview flow land in Sprint 2.")
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.participantLabel?.isEmpty == false ? session.participantLabel! : session.guideName)
                                    .font(.headline)
                                Text(session.guideName)
                                    .foregroundStyle(.secondary)
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("Must Cover: \(session.answeredMustCoverCount)/\(session.mustCoverQuestionCount)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
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
        .alert("Session Setup Arrives In Sprint 2", isPresented: $bindable.showSprintTwoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Guide selection and the active interview sheet land in Sprint 2. Sprint 1 already enforces the workspace gate and local fallback behavior.")
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
