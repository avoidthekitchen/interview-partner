import SwiftUI
import InterviewPartnerServices

public struct InterviewPartnerRootView: View {
    private let appEnvironment: AppEnvironment
    @State private var workspaceRefreshToken = UUID()
    @AppStorage(InterviewPartnerAppStorageKey.hasAcknowledgedPrivacyDisclosure)
    private var hasAcknowledgedPrivacyDisclosure = false
    @State private var showPrivacyDisclosure = false

    public init(appEnvironment: AppEnvironment) {
        self.appEnvironment = appEnvironment
    }

    public var body: some View {
        TabView {
            NavigationStack {
                SessionListView(
                    guideRepository: appEnvironment.guideRepository,
                    sessionRepository: appEnvironment.sessionRepository,
                    workspaceExporter: appEnvironment.workspaceExporter,
                    permissionManager: appEnvironment.permissionManager,
                    makeTranscriptionService: appEnvironment.makeTranscriptionService,
                    workspaceRefreshToken: workspaceRefreshToken
                )
            }
            .tabItem {
                Label("Sessions", systemImage: "waveform.path.ecg")
            }

            NavigationStack {
                GuideListView(guideRepository: appEnvironment.guideRepository)
            }
            .tabItem {
                Label("Guides", systemImage: "list.bullet.clipboard")
            }

            NavigationStack {
                SettingsView(
                    workspaceExporter: appEnvironment.workspaceExporter,
                    onWorkspaceUpdated: {
                        workspaceRefreshToken = UUID()
                    }
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .onAppear {
            if !hasAcknowledgedPrivacyDisclosure && !showPrivacyDisclosure {
                showPrivacyDisclosure = true
            }
        }
        .onChange(of: hasAcknowledgedPrivacyDisclosure) { _, hasAcknowledged in
            if !hasAcknowledged {
                showPrivacyDisclosure = true
            }
        }
        .fullScreenCover(isPresented: $showPrivacyDisclosure) {
            PrivacyDisclosureSheet(
                title: "Privacy Disclosure",
                dismissLabel: "Continue",
                onDismiss: {
                    showPrivacyDisclosure = false
                }
            )
        }
    }
}
