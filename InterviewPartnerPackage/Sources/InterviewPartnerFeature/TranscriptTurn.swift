import Foundation
import SwiftData

public struct TranscriptTurn: Identifiable, Hashable {
    public let id: UUID
    public let speakerLabel: String
    public let text: String
    public let createdAt: Date
    public let startTimeSeconds: TimeInterval?
    public let endTimeSeconds: TimeInterval?
    public let speakerMatchConfidence: Double?

    public init(
        id: UUID = UUID(),
        speakerLabel: String = "Unclear",
        text: String,
        createdAt: Date = .now,
        startTimeSeconds: TimeInterval? = nil,
        endTimeSeconds: TimeInterval? = nil,
        speakerMatchConfidence: Double? = nil
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.text = text
        self.createdAt = createdAt
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.speakerMatchConfidence = speakerMatchConfidence
    }
}

@Model
public final class TranscriptTurnRecord {
    public var id: UUID
    public var speakerLabel: String
    public var text: String
    public var createdAt: Date
    public var startTimeSeconds: Double?
    public var endTimeSeconds: Double?
    public var speakerMatchConfidence: Double?

    public init(
        id: UUID = UUID(),
        speakerLabel: String = "Unclear",
        text: String,
        createdAt: Date = .now,
        startTimeSeconds: Double? = nil,
        endTimeSeconds: Double? = nil,
        speakerMatchConfidence: Double? = nil
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.text = text
        self.createdAt = createdAt
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.speakerMatchConfidence = speakerMatchConfidence
    }
}
