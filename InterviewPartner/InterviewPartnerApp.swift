import SwiftUI
import SwiftData
import InterviewPartnerFeatures
import InterviewPartnerServices

@main
struct InterviewPartnerApp: App {
    private let appEnvironment: AppEnvironment

    init() {
        do {
            appEnvironment = try AppEnvironment()
        } catch {
            fatalError("Failed to bootstrap app environment: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            InterviewPartnerRootView(appEnvironment: appEnvironment)
        }
        .modelContainer(appEnvironment.modelContainer)
    }
}
