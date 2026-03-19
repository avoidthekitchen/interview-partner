import Foundation

struct VadBoundaryTracker: Sendable {
    private var openSpeechStartSeconds: Double?
    private var completedWindows: [UtteranceWindow] = []

    mutating func reset() {
        openSpeechStartSeconds = nil
        completedWindows.removeAll()
    }

    mutating func ingest(event: VadBoundaryEvent) {
        switch event.kind {
        case .speechStart:
            if openSpeechStartSeconds == nil {
                openSpeechStartSeconds = event.timeSeconds
            }
        case .speechEnd:
            guard let openSpeechStartSeconds else { return }
            completedWindows.append(
                UtteranceWindow(
                    startSeconds: openSpeechStartSeconds,
                    endSeconds: max(event.timeSeconds, openSpeechStartSeconds),
                    source: .vad
                )
            )
            self.openSpeechStartSeconds = nil
        }
    }

    mutating func consumeBestWindow(
        audioDurationSeconds: Double,
        previousBoundarySeconds: Double,
        eouDebounceMs: Int
    ) -> (window: UtteranceWindow, missedSpeechEnd: Bool) {
        if !completedWindows.isEmpty {
            return (completedWindows.removeFirst(), false)
        }

        if let openSpeechStartSeconds {
            return (
                UtteranceWindow(
                    startSeconds: openSpeechStartSeconds,
                    endSeconds: audioDurationSeconds,
                    source: .vad
                ),
                true
            )
        }

        return (
            Self.fallbackWindow(
                previousBoundarySeconds: previousBoundarySeconds,
                audioDurationSeconds: audioDurationSeconds,
                eouDebounceMs: eouDebounceMs
            ),
            true
        )
    }

    static func fallbackWindow(
        previousBoundarySeconds: Double,
        audioDurationSeconds: Double,
        eouDebounceMs: Int
    ) -> UtteranceWindow {
        let estimatedEnd = max(
            previousBoundarySeconds,
            audioDurationSeconds - (Double(eouDebounceMs) / 1000.0)
        )
        return UtteranceWindow(
            startSeconds: previousBoundarySeconds,
            endSeconds: estimatedEnd,
            source: .debounceFallback
        )
    }
}
