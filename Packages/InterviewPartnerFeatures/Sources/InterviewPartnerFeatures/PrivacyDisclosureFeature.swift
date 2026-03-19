import SwiftUI

enum InterviewPartnerAppStorageKey {
    static let hasAcknowledgedPrivacyDisclosure = "privacyDisclosureAcknowledged"
}

struct PrivacyDisclosureSheet: View {
    let title: String
    let dismissLabel: String
    let onDismiss: () -> Void

    @AppStorage(InterviewPartnerAppStorageKey.hasAcknowledgedPrivacyDisclosure)
    private var hasAcknowledgedPrivacyDisclosure = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy")
                            .font(.largeTitle.bold())
                        Text("Audio is processed on your device and never uploaded without your permission.")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }

                    disclosureCard(
                        title: "On-device only",
                        body: "Live audio capture, transcription, and speaker separation stay on this device in Sprint 4."
                    )

                    disclosureCard(
                        title: "No silent uploads",
                        body: "Interview Partner does not send your audio or transcript anywhere unless a future feature explicitly asks you to."
                    )

                    disclosureCard(
                        title: "What is stored",
                        body: "The app stores transcript text, question coverage, and notes locally so your session can survive interruptions and export reliably."
                    )
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(dismissLabel) {
                    hasAcknowledgedPrivacyDisclosure = true
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled(!hasAcknowledgedPrivacyDisclosure)
    }

    private func disclosureCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
