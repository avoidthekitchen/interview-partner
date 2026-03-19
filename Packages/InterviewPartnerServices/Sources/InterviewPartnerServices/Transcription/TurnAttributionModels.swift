import Foundation

public struct DiarizedSegment: Identifiable, Codable, Hashable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id
        case speakerIndex = "speaker_index"
        case startTimeSeconds = "start_time_seconds"
        case endTimeSeconds = "end_time_seconds"
        case isFinal = "is_final"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        speakerIndex = try container.decode(Int.self, forKey: .speakerIndex)
        startTimeSeconds = try container.decode(TimeInterval.self, forKey: .startTimeSeconds)
        endTimeSeconds = try container.decode(TimeInterval.self, forKey: .endTimeSeconds)
        isFinal = try container.decode(Bool.self, forKey: .isFinal)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(speakerIndex, forKey: .speakerIndex)
        try container.encode(startTimeSeconds, forKey: .startTimeSeconds)
        try container.encode(endTimeSeconds, forKey: .endTimeSeconds)
        try container.encode(isFinal, forKey: .isFinal)
    }
}

public struct DiarizationSnapshot: Codable, Hashable, Sendable {
    public let totalAudioSeconds: Double
    public let segments: [DiarizedSegment]
    public let attributedSpeakerCount: Int

    public init(
        totalAudioSeconds: Double,
        segments: [DiarizedSegment],
        attributedSpeakerCount: Int
    ) {
        self.totalAudioSeconds = totalAudioSeconds
        self.segments = segments
        self.attributedSpeakerCount = attributedSpeakerCount
    }
}

public enum BoundarySource: String, Codable, CaseIterable, Sendable {
    case vad
    case debounceFallback
    case replayFixture
}

public struct UtteranceWindow: Codable, Hashable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let source: BoundarySource

    public init(startSeconds: Double, endSeconds: Double, source: BoundarySource) {
        self.startSeconds = startSeconds
        self.endSeconds = max(endSeconds, startSeconds)
        self.source = source
    }
}

public struct VadBoundaryEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case speechStart
        case speechEnd
    }

    public let kind: Kind
    public let timeSeconds: Double

    public init(kind: Kind, timeSeconds: Double) {
        self.kind = kind
        self.timeSeconds = timeSeconds
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case timeSeconds = "time_seconds"
    }
}

public struct ReplayFrame: Codable, Sendable {
    public var elapsedSeconds: Double
    public var cumulativeTranscript: String?
    public var diarizationSegments: [DiarizedSegment]
    public var vadEvent: VadBoundaryEvent?
    public var eouDetected: Bool

    public init(
        elapsedSeconds: Double,
        cumulativeTranscript: String?,
        diarizationSegments: [DiarizedSegment],
        vadEvent: VadBoundaryEvent?,
        eouDetected: Bool
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.cumulativeTranscript = cumulativeTranscript
        self.diarizationSegments = diarizationSegments
        self.vadEvent = vadEvent
        self.eouDetected = eouDetected
    }

    enum CodingKeys: String, CodingKey {
        case elapsedSeconds = "elapsed_seconds"
        case cumulativeTranscript = "cumulative_transcript"
        case diarizationSegments = "diarization_segments"
        case vadEvent = "vad_event"
        case eouDetected = "eou_detected"
    }
}

struct DiarizationTurnAttribution: Codable, Hashable, Sendable {
    let speakerIndex: Int?
    let speakerLabel: String
    let estimatedStartTimeSeconds: TimeInterval
    let estimatedEndTimeSeconds: TimeInterval
    let confidence: Double
    let note: String
}

func defaultSpeakerLabel(for speakerIndex: Int) -> String {
    switch speakerIndex {
    case 0:
        return "Speaker A"
    case 1:
        return "Speaker B"
    case 2:
        return "Speaker C"
    case 3:
        return "Speaker D"
    default:
        return "Speaker \(speakerIndex + 1)"
    }
}
