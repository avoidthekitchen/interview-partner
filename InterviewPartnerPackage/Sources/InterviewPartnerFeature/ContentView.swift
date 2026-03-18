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
                    recommendationCard
                    partialCard
                    transcriptList
                    diarizationCard
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
            Text("Sprint 0.5 Diarization Spike")
                .font(.title.weight(.bold))
            Text("Live transcript turns + provisional speaker labels")
                .font(.title3.weight(.semibold))
            Text("The EOU callback still only returns transcript strings, so this spike aligns finalized turns to a separate Sortformer diarization timeline using the shared microphone stream.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(coordinator.statusMessage, systemImage: coordinator.isRecording ? "waveform.circle.fill" : "mic.circle")
                .foregroundStyle(coordinator.errorMessage == nil ? Color.primary : Color.red)
            Label(coordinator.diarizationStatusMessage, systemImage: "person.2.wave.2")
                .foregroundStyle(.secondary)

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
                Text("Diarization segments: \(coordinator.diarizedSegments.count)")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote.monospacedDigit())
        }
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sprint 2 Recommendation")
                .font(.headline)
            Text(coordinator.sprintRecommendation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                            Text("\(turn.speakerLabel) · \(turn.createdAt.formatted(date: .omitted, time: .standard))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let start = turn.startTimeSeconds, let end = turn.endTimeSeconds {
                                Text(
                                    "EOU-aligned window \(formatted(seconds: start))-\(formatted(seconds: end)) · confidence \(Int((turn.speakerMatchConfidence ?? 0) * 100))%"
                                )
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
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

    private var diarizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Diarization Segments")
                .font(.headline)

            if coordinator.diarizedSegments.isEmpty {
                Text("No diarization segments yet. Start speaking and pause so Sortformer has audio to align against.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(coordinator.diarizedSegments.suffix(8))) { segment in
                        Text(
                            "Speaker \(segment.speakerIndex) · \(formatted(seconds: segment.startTimeSeconds))-\(formatted(seconds: segment.endTimeSeconds)) · \(segment.isFinal ? "final" : "tentative")"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(segment.isFinal ? .primary : .secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verification target")
                .font(.headline)
            Text("1. Tap start.\n2. Confirm partial text updates while speaking.\n3. Pause briefly so the shorter EOU debounce finalizes a turn.\n4. Confirm the turn receives a provisional Speaker A/B label.\n5. Manual re-test still needed for locked-screen behavior with ASR + diarization both active.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func formatted(seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
