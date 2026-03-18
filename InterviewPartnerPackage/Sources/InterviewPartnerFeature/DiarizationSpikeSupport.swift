import AVFoundation
import FluidAudio
import Foundation

public struct DiarizedSegment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let speakerIndex: Int
    public let startTimeSeconds: TimeInterval
    public let endTimeSeconds: TimeInterval
    public let isFinal: Bool

    public init(
        id: UUID = UUID(),
        speakerIndex: Int,
        startTimeSeconds: TimeInterval,
        endTimeSeconds: TimeInterval,
        isFinal: Bool
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.isFinal = isFinal
    }
}

public struct DiarizationTurnAttribution: Hashable, Sendable {
    public let speakerIndex: Int?
    public let speakerLabel: String
    public let estimatedStartTimeSeconds: TimeInterval
    public let estimatedEndTimeSeconds: TimeInterval
    public let confidence: Double
    public let note: String

    public init(
        speakerIndex: Int?,
        speakerLabel: String,
        estimatedStartTimeSeconds: TimeInterval,
        estimatedEndTimeSeconds: TimeInterval,
        confidence: Double,
        note: String
    ) {
        self.speakerIndex = speakerIndex
        self.speakerLabel = speakerLabel
        self.estimatedStartTimeSeconds = estimatedStartTimeSeconds
        self.estimatedEndTimeSeconds = estimatedEndTimeSeconds
        self.confidence = confidence
        self.note = note
    }
}

public struct DiarizationSnapshot: Hashable, Sendable {
    public let totalAudioSeconds: Double
    public let segments: [DiarizedSegment]
    public let attributedSpeakerCount: Int

    public init(totalAudioSeconds: Double, segments: [DiarizedSegment], attributedSpeakerCount: Int) {
        self.totalAudioSeconds = totalAudioSeconds
        self.segments = segments
        self.attributedSpeakerCount = attributedSpeakerCount
    }
}

struct DominantSpeakerMatcher {
    static func attributeNextTurn(
        segments: [DiarizedSegment],
        previousBoundarySeconds: TimeInterval,
        audioDurationSeconds: TimeInterval,
        eouDebounceMs: Int,
        speakerLabel: (Int) -> String
    ) -> DiarizationTurnAttribution {
        let estimatedEnd = max(previousBoundarySeconds, audioDurationSeconds - (Double(eouDebounceMs) / 1000.0))
        let estimatedStart = previousBoundarySeconds
        let windowDuration = max(estimatedEnd - estimatedStart, 0.001)

        var overlapBySpeaker: [Int: Double] = [:]
        for segment in segments {
            let overlap = overlapDuration(
                segmentStart: segment.startTimeSeconds,
                segmentEnd: segment.endTimeSeconds,
                windowStart: estimatedStart,
                windowEnd: estimatedEnd
            )

            guard overlap > 0 else { continue }
            overlapBySpeaker[segment.speakerIndex, default: 0] += overlap
        }

        let rankedSpeakers = overlapBySpeaker.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }

        guard let topSpeaker = rankedSpeakers.first else {
            return fallbackAttribution(
                segments: segments,
                estimatedStart: estimatedStart,
                estimatedEnd: estimatedEnd
            )
        }

        let secondOverlap = rankedSpeakers.dropFirst().first?.value ?? 0
        let dominantOverlap = topSpeaker.value
        let confidence = min(1.0, dominantOverlap / windowDuration)

        if dominantOverlap < 0.25 || (secondOverlap > 0 && dominantOverlap / secondOverlap < 1.25) {
            return DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Unclear",
                estimatedStartTimeSeconds: estimatedStart,
                estimatedEndTimeSeconds: estimatedEnd,
                confidence: confidence,
                note: "Competing diarization segments overlap this EOU window."
            )
        }

        return DiarizationTurnAttribution(
            speakerIndex: topSpeaker.key,
            speakerLabel: speakerLabel(topSpeaker.key),
            estimatedStartTimeSeconds: estimatedStart,
            estimatedEndTimeSeconds: estimatedEnd,
            confidence: confidence,
            note: "Mapped from dominant diarization overlap within the EOU-aligned window."
        )
    }

    private static func fallbackAttribution(
        segments: [DiarizedSegment],
        estimatedStart: TimeInterval,
        estimatedEnd: TimeInterval
    ) -> DiarizationTurnAttribution {
        let nearbySegment = segments
            .filter { $0.endTimeSeconds >= estimatedStart - 0.5 && $0.startTimeSeconds <= estimatedEnd + 0.5 }
            .max { lhs, rhs in
                lhs.endTimeSeconds < rhs.endTimeSeconds
            }

        guard let nearbySegment else {
            return DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Unclear",
                estimatedStartTimeSeconds: estimatedStart,
                estimatedEndTimeSeconds: estimatedEnd,
                confidence: 0,
                note: "No diarization segment overlapped the EOU-aligned window."
            )
        }

        return DiarizationTurnAttribution(
            speakerIndex: nearbySegment.speakerIndex,
            speakerLabel: "Unclear",
            estimatedStartTimeSeconds: estimatedStart,
            estimatedEndTimeSeconds: estimatedEnd,
            confidence: 0.2,
            note: "Only a nearby diarization segment was available, so this turn remains unclear."
        )
    }

    private static func overlapDuration(
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        windowStart: TimeInterval,
        windowEnd: TimeInterval
    ) -> Double {
        max(0, min(segmentEnd, windowEnd) - max(segmentStart, windowStart))
    }
}

actor LiveDiarizationSpikeEngine {
    private let audioConverter = AudioConverter()
    private let diarizer: SortformerDiarizer

    private var hasLoadedModels = false
    private var totalSamples = 0
    private var lastAssignedBoundarySeconds: TimeInterval = 0
    private var speakerLabelsByIndex: [Int: String] = [:]

    init(config: SortformerConfig = .default) {
        diarizer = SortformerDiarizer(config: config, postProcessingConfig: .default)
    }

    func prepareIfNeeded() async throws {
        guard !hasLoadedModels else { return }

        let models = try await SortformerModels.loadFromHuggingFace(config: diarizer.config)
        diarizer.initialize(models: models)
        hasLoadedModels = true
    }

    func reset() {
        diarizer.reset()
        totalSamples = 0
        lastAssignedBoundarySeconds = 0
        speakerLabelsByIndex.removeAll()
    }

    func ingest(_ buffer: AVAudioPCMBuffer) throws {
        let samples = try audioConverter.resampleBuffer(buffer)
        totalSamples += samples.count
        _ = try diarizer.processSamples(samples)
    }

    func finalizeAndSnapshot() -> DiarizationSnapshot {
        diarizer.timeline.finalize()
        return snapshot(includeTentative: false)
    }

    func currentSnapshot() -> DiarizationSnapshot {
        snapshot(includeTentative: true)
    }

    func attributeNextTurn(eouDebounceMs: Int) -> DiarizationTurnAttribution {
        let currentSnapshot = snapshot(includeTentative: true)
        let attribution = DominantSpeakerMatcher.attributeNextTurn(
            segments: currentSnapshot.segments,
            previousBoundarySeconds: lastAssignedBoundarySeconds,
            audioDurationSeconds: currentSnapshot.totalAudioSeconds,
            eouDebounceMs: eouDebounceMs,
            speakerLabel: speakerLabel(for:)
        )

        lastAssignedBoundarySeconds = attribution.estimatedEndTimeSeconds
        return attribution
    }

    private func snapshot(includeTentative: Bool) -> DiarizationSnapshot {
        let finalizedSegments = diarizer.timeline.segments.enumerated().flatMap { speakerIndex, segments in
            segments.map { segment in
                DiarizedSegment(
                    speakerIndex: speakerIndex,
                    startTimeSeconds: TimeInterval(segment.startTime),
                    endTimeSeconds: TimeInterval(segment.endTime),
                    isFinal: true
                )
            }
        }

        let tentativeSegments: [DiarizedSegment]
        if includeTentative {
            tentativeSegments = diarizer.timeline.tentativeSegments.enumerated().flatMap { speakerIndex, segments in
                segments.map { segment in
                    DiarizedSegment(
                        speakerIndex: speakerIndex,
                        startTimeSeconds: TimeInterval(segment.startTime),
                        endTimeSeconds: TimeInterval(segment.endTime),
                        isFinal: false
                    )
                }
            }
        } else {
            tentativeSegments = []
        }

        let allSegments = (finalizedSegments + tentativeSegments)
            .sorted { lhs, rhs in
                if lhs.startTimeSeconds == rhs.startTimeSeconds {
                    return lhs.speakerIndex < rhs.speakerIndex
                }
                return lhs.startTimeSeconds < rhs.startTimeSeconds
            }

        return DiarizationSnapshot(
            totalAudioSeconds: Double(totalSamples) / 16_000.0,
            segments: allSegments,
            attributedSpeakerCount: Set(allSegments.map(\.speakerIndex)).count
        )
    }

    private func speakerLabel(for speakerIndex: Int) -> String {
        if let existingLabel = speakerLabelsByIndex[speakerIndex] {
            return existingLabel
        }

        let labelIndex = speakerLabelsByIndex.count
        let label: String
        switch labelIndex {
        case 0:
            label = "Speaker A"
        case 1:
            label = "Speaker B"
        case 2:
            label = "Speaker C"
        case 3:
            label = "Speaker D"
        default:
            label = "Speaker \(speakerIndex + 1)"
        }

        speakerLabelsByIndex[speakerIndex] = label
        return label
    }
}
