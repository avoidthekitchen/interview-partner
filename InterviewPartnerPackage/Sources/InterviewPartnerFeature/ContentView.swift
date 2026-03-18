import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptTurnRecord.createdAt) private var persistedTurns: [TranscriptTurnRecord]
    @State private var coordinator = TranscriptionSpikeCoordinator()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    controlRow
                    partialCard
                    transcriptList
                    footerCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .task {
            coordinator.configurePersistence { record in
                modelContext.insert(record)

                do {
                    try modelContext.save()
                } catch {
                    assertionFailure("Failed to persist transcript turn: \(error)")
                }
            }
        }
        .onDisappear {
            coordinator.stopIfNeeded()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sprint 0 Spike")
                .font(.title.weight(.bold))
            Text("Live transcription only")
                .font(.title3.weight(.semibold))
            Text("Sprint 0 proves FluidAudio streaming transcription, partial text, and finalized turns. Speaker labeling is deferred to Sprint 0.5 because the current EOU callback does not expose speaker IDs.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(coordinator.statusMessage, systemImage: coordinator.isRecording ? "waveform.circle.fill" : "mic.circle")
                .foregroundStyle(coordinator.errorMessage == nil ? Color.primary : Color.red)

            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var controlRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(coordinator.isRecording ? "Stop Transcription" : "Start Transcription") {
                coordinator.toggleRecording()
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Finalized turns: \(coordinator.turns.count)")
                Text("SwiftData records: \(persistedTurns.count)")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote.monospacedDigit())
        }
    }

    private var partialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Partial")
                .font(.headline)
            Text(coordinator.partialText.isEmpty ? "Start speaking to see in-progress text." : coordinator.partialText)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .padding()
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var transcriptList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finalized transcript")
                .font(.headline)

            if coordinator.turns.isEmpty {
                ContentUnavailableView(
                    "No Finalized Turns",
                    systemImage: "text.quote",
                    description: Text("Tap start, allow microphone access, and pause briefly between sentences so the EOU callback can finalize a turn.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(coordinator.turns) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(turn.createdAt.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(turn.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verification target")
                .font(.headline)
            Text("1. Tap start.\n2. Confirm partial text updates while speaking.\n3. Pause to let EOU finalize a turn.\n4. Confirm finalized text is appended and persisted.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
