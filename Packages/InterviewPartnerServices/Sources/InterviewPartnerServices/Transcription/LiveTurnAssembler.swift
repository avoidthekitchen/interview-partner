import Foundation
import InterviewPartnerDomain

struct LiveTurnAssemblyResult: Sendable {
    let turn: TranscriptTurn
    let gap: TranscriptGap?
}

enum LiveTurnAssembler {
    static func assembleTurn(
        sessionID: UUID,
        startedAt: Date,
        previousTurnEndTimeSeconds: TimeInterval?,
        text: String,
        diarizationAvailable: Bool,
        window: UtteranceWindow,
        diarizationSegments: [DiarizedSegment],
        gapThresholdSeconds: TimeInterval,
        tuning: DiarizationTuning
    ) -> LiveTurnAssemblyResult {
        let attribution: DiarizationTurnAttribution
        if diarizationAvailable {
            attribution = DominantSpeakerMatcher.attributeTurn(
                segments: diarizationSegments,
                windowStart: window.startSeconds,
                windowEnd: window.endSeconds,
                tuning: tuning,
                speakerLabel: defaultSpeakerLabel(for:)
            )
        } else {
            attribution = DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Speaker A",
                estimatedStartTimeSeconds: window.startSeconds,
                estimatedEndTimeSeconds: window.endSeconds,
                confidence: 0,
                note: "Fallback transcription does not provide diarization."
            )
        }

        let gap: TranscriptGap?
        if let previousTurnEndTimeSeconds,
           attribution.estimatedStartTimeSeconds - previousTurnEndTimeSeconds >= gapThresholdSeconds {
            gap = TranscriptGap(
                sessionID: sessionID,
                startTimestamp: startedAt.addingTimeInterval(previousTurnEndTimeSeconds),
                endTimestamp: startedAt.addingTimeInterval(attribution.estimatedStartTimeSeconds),
                reason: .transcriptionUnavailable
            )
        } else {
            gap = nil
        }

        let turn = TranscriptTurn(
            speakerLabel: attribution.speakerLabel,
            text: text,
            timestamp: startedAt.addingTimeInterval(attribution.estimatedEndTimeSeconds),
            isFinal: true,
            startTimeSeconds: attribution.estimatedStartTimeSeconds,
            endTimeSeconds: attribution.estimatedEndTimeSeconds,
            speakerMatchConfidence: diarizationAvailable ? attribution.confidence : nil,
            speakerLabelIsProvisional: diarizationAvailable
        )

        return LiveTurnAssemblyResult(turn: turn, gap: gap)
    }

    static func reconcileTurns(
        snapshot: DiarizationSnapshot?,
        turns: [TranscriptTurn],
        tuning: DiarizationTuning
    ) -> [TranscriptTurn] {
        guard let snapshot else {
            return turns
        }

        var previousBoundary: TimeInterval = 0
        return turns.map { turn in
            let start = turn.startTimeSeconds ?? previousBoundary
            let end = max(turn.endTimeSeconds ?? start, start)
            let attribution = DominantSpeakerMatcher.attributeTurn(
                segments: snapshot.segments.filter(\.isFinal),
                windowStart: start,
                windowEnd: end,
                tuning: tuning,
                speakerLabel: defaultSpeakerLabel(for:)
            )
            previousBoundary = end

            var reconciled = turn
            reconciled.speakerLabel = attribution.speakerLabel
            reconciled.speakerMatchConfidence = attribution.confidence
            reconciled.speakerLabelIsProvisional = false
            return reconciled
        }
    }
}

private enum DominantSpeakerMatcher {
    static func attributeTurn(
        segments: [DiarizedSegment],
        windowStart: TimeInterval,
        windowEnd: TimeInterval,
        tuning: DiarizationTuning,
        speakerLabel: (Int) -> String
    ) -> DiarizationTurnAttribution {
        let sanitizedEnd = max(windowEnd, windowStart)
        let windowDuration = max(sanitizedEnd - windowStart, 0.001)

        var overlapBySpeaker: [Int: Double] = [:]
        for segment in segments {
            let overlap = max(
                0,
                min(segment.endTimeSeconds, sanitizedEnd) - max(segment.startTimeSeconds, windowStart)
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
            return DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Unclear",
                estimatedStartTimeSeconds: windowStart,
                estimatedEndTimeSeconds: sanitizedEnd,
                confidence: 0,
                note: "No diarization segment overlapped the turn window."
            )
        }

        let secondOverlap = rankedSpeakers.dropFirst().first?.value ?? 0
        let dominantOverlap = topSpeaker.value
        let confidence = min(1.0, dominantOverlap / windowDuration)

        if dominantOverlap < tuning.minimumDominantOverlapSeconds
            || (secondOverlap > 0 && dominantOverlap / secondOverlap < tuning.dominantSpeakerRatioThreshold)
        {
            return DiarizationTurnAttribution(
                speakerIndex: nil,
                speakerLabel: "Unclear",
                estimatedStartTimeSeconds: windowStart,
                estimatedEndTimeSeconds: sanitizedEnd,
                confidence: confidence,
                note: "Competing diarization segments overlap this turn window."
            )
        }

        return DiarizationTurnAttribution(
            speakerIndex: topSpeaker.key,
            speakerLabel: speakerLabel(topSpeaker.key),
            estimatedStartTimeSeconds: windowStart,
            estimatedEndTimeSeconds: sanitizedEnd,
            confidence: confidence,
            note: "Mapped from dominant diarization overlap within the turn window."
        )
    }
}
