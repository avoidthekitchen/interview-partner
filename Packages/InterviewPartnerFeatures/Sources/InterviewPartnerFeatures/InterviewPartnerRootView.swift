import SwiftUI
import InterviewPartnerServices

public struct InterviewPartnerRootView: View {
    private let appEnvironment: Sprint1AppEnvironment
    @State private var workspaceRefreshToken = UUID()

    public init(appEnvironment: Sprint1AppEnvironment) {
        self.appEnvironment = appEnvironment
    }

    public var body: some View {
        TabView {
            NavigationStack {
                SessionListView(
                    sessionRepository: appEnvironment.sessionRepository,
                    workspaceExporter: appEnvironment.workspaceExporter,
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
    }
}
