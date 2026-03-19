import FluidAudio
import Foundation

public struct DiarizationTuning: @unchecked Sendable {
    public let name: String
    public let sortformerConfig: SortformerConfig
    public let sortformerPostProcessing: SortformerPostProcessingConfig
    public let minimumDominantOverlapSeconds: Double
    public let dominantSpeakerRatioThreshold: Double

    public init(
        name: String,
        sortformerConfig: SortformerConfig = .default,
        sortformerPostProcessing: SortformerPostProcessingConfig = .default,
        minimumDominantOverlapSeconds: Double = 0.15,
        dominantSpeakerRatioThreshold: Double = 1.25
    ) {
        self.name = name
        self.sortformerConfig = sortformerConfig
        self.sortformerPostProcessing = sortformerPostProcessing
        self.minimumDominantOverlapSeconds = minimumDominantOverlapSeconds
        self.dominantSpeakerRatioThreshold = dominantSpeakerRatioThreshold
    }

    public static let productionDefault = DiarizationTuning(name: "production_default")

    public static let benchmarkPinnedTuned = DiarizationTuning(
        name: "pinned_tuned",
        sortformerConfig: .default,
        sortformerPostProcessing: SortformerPostProcessingConfig(
            onsetThreshold: 0.48,
            offsetThreshold: 0.52,
            onsetPadSeconds: 0.08,
            offsetPadSeconds: 0.08,
            minDurationOn: 0.08,
            minDurationOff: 0.08
        ),
        minimumDominantOverlapSeconds: 0.12,
        dominantSpeakerRatioThreshold: 1.15
    )
}
