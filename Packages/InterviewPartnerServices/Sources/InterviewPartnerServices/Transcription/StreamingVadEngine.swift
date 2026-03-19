import AVFoundation
import FluidAudio
import Foundation

actor StreamingVadEngine {
    private let audioConverter = AudioConverter()
    private let segmentationConfig: VadSegmentationConfig

    private var manager: VadManager?
    private var streamState = VadStreamState.initial()
    private var bufferedSamples: [Float] = []

    init(segmentationConfig: VadSegmentationConfig = .default) {
        self.segmentationConfig = segmentationConfig
    }

    func prepareIfNeeded() async throws {
        guard manager == nil else { return }
        manager = try await VadManager()
    }

    func reset() {
        streamState = .initial()
        bufferedSamples.removeAll()
    }

    func ingest(_ buffer: AVAudioPCMBuffer) async throws -> [VadBoundaryEvent] {
        guard let manager else { return [] }

        bufferedSamples.append(contentsOf: try audioConverter.resampleBuffer(buffer))
        var events: [VadBoundaryEvent] = []

        while bufferedSamples.count >= VadManager.chunkSize {
            let chunk = Array(bufferedSamples.prefix(VadManager.chunkSize))
            bufferedSamples.removeFirst(VadManager.chunkSize)

            let result = try await manager.processStreamingChunk(
                chunk,
                state: streamState,
                config: segmentationConfig,
                returnSeconds: true
            )
            streamState = result.state

            if let event = result.event, let time = event.time {
                events.append(
                    VadBoundaryEvent(
                        kind: event.isStart ? .speechStart : .speechEnd,
                        timeSeconds: time
                    )
                )
            }
        }

        return events
    }

    func currentAudioDurationSeconds() -> Double {
        Double(streamState.processedSamples) / Double(VadManager.sampleRate)
    }
}
