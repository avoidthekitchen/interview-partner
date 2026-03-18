import SwiftUI
import SwiftData
import InterviewPartnerFeatures
import InterviewPartnerServices

@main
struct InterviewPartnerApp: App {
    private let appEnvironment: Sprint1AppEnvironment

    init() {
        do {
            appEnvironment = try Sprint1AppEnvironment()
        } catch {
            fatalError("Failed to bootstrap Sprint 1 environment: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            InterviewPartnerRootView(appEnvironment: appEnvironment)
        }
        .modelContainer(appEnvironment.modelContainer)
    }
}
