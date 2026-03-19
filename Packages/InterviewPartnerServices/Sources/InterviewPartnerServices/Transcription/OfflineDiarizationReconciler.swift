import Foundation
import FluidAudio
import InterviewPartnerDomain

public struct FinalSpeakerReconciliationResult: Sendable {
    public var turns: [TranscriptTurn]
    public var runtimeSeconds: Double
    public var usedOfflineDiarization: Bool

    public init(turns: [TranscriptTurn], runtimeSeconds: Double, usedOfflineDiarization: Bool) {
        self.turns = turns
        self.runtimeSeconds = runtimeSeconds
        self.usedOfflineDiarization = usedOfflineDiarization
    }
}

protocol OfflineDiarizationProviding: Sendable {
    func process(audioAt url: URL) async throws -> DiarizationResult
}

final class FluidAudioOfflineDiarizationProvider: OfflineDiarizationProviding, @unchecked Sendable {
    private let manager: OfflineDiarizerManager
    private var isPrepared = false

    init(config: OfflineDiarizerConfig = .default) {
        manager = OfflineDiarizerManager(config: config)
    }

    func process(audioAt url: URL) async throws -> DiarizationResult {
        if !isPrepared {
            try await manager.prepareModels()
            isPrepared = true
        }
        return try await manager.process(url)
    }
}

actor OfflineDiarizationReconciler {
    private let provider: any OfflineDiarizationProviding
    private let tuning: DiarizationTuning
    private let runtimeLimitFactor: Double

    init(
        provider: any OfflineDiarizationProviding = FluidAudioOfflineDiarizationProvider(),
        tuning: DiarizationTuning = .productionDefault,
        runtimeLimitFactor: Double = 1.5
    ) {
        self.provider = provider
        self.tuning = tuning
        self.runtimeLimitFactor = runtimeLimitFactor
    }

    func reconcile(
        turns: [TranscriptTurn],
        audioURL: URL?
    ) async -> FinalSpeakerReconciliationResult {
        guard let audioURL else {
            return FinalSpeakerReconciliationResult(
                turns: finalizeFallbackTurns(turns),
                runtimeSeconds: 0,
                usedOfflineDiarization: false
            )
        }

        let start = Date()
        do {
            let diarizationResult = try await provider.process(audioAt: audioURL)
            let runtimeSeconds = Date().timeIntervalSince(start)
            let maxTurnEnd = turns.compactMap(\.endTimeSeconds).max() ?? 0

            guard maxTurnEnd <= 0 || runtimeSeconds <= maxTurnEnd * runtimeLimitFactor else {
                return FinalSpeakerReconciliationResult(
                    turns: finalizeFallbackTurns(turns),
                    runtimeSeconds: runtimeSeconds,
                    usedOfflineDiarization: false
                )
            }

            let snapshot = DiarizationSnapshot(
                totalAudioSeconds: maxTurnEnd,
                segments: diarizationResult.segments.map { segment in
                    DiarizedSegment(
                        speakerIndex: Self.speakerIndex(for: segment.speakerId),
                        startTimeSeconds: Double(segment.startTimeSeconds),
                        endTimeSeconds: Double(segment.endTimeSeconds),
                        isFinal: true
                    )
                },
                attributedSpeakerCount: Set(diarizationResult.segments.map(\.speakerId)).count
            )

            return FinalSpeakerReconciliationResult(
                turns: LiveTurnAssembler.reconcileTurns(
                    snapshot: snapshot,
                    turns: turns,
                    tuning: tuning
                ),
                runtimeSeconds: runtimeSeconds,
                usedOfflineDiarization: true
            )
        } catch {
            let runtimeSeconds = Date().timeIntervalSince(start)
            return FinalSpeakerReconciliationResult(
                turns: finalizeFallbackTurns(turns),
                runtimeSeconds: runtimeSeconds,
                usedOfflineDiarization: false
            )
        }
    }

    private func finalizeFallbackTurns(_ turns: [TranscriptTurn]) -> [TranscriptTurn] {
        turns.map { turn in
            var turn = turn
            turn.speakerLabelIsProvisional = false
            return turn
        }
    }

    private static func speakerIndex(for speakerID: String) -> Int {
        if let parsed = Int(speakerID.filter(\.isNumber)) {
            return max(parsed - 1, 0)
        }
        return abs(speakerID.hashValue % 4)
    }
}
