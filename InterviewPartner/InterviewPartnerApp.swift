import SwiftUI
import SwiftData
import InterviewPartnerFeature

@main
struct InterviewPartnerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TranscriptTurnRecord.self])
    }
}
