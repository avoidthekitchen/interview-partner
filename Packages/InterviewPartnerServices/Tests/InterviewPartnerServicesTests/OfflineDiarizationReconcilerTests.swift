import AVFoundation
import Foundation
import Testing
import FluidAudio
import InterviewPartnerDomain
@testable import InterviewPartnerServices

private struct StubOfflineProvider: OfflineDiarizationProviding {
    let result: DiarizationResult

    func process(audioAt url: URL) async throws -> DiarizationResult {
        result
    }
}

private struct FailingOfflineProvider: OfflineDiarizationProviding {
    struct StubError: Error {}

    func process(audioAt url: URL) async throws -> DiarizationResult {
        throw StubError()
    }
}

@Test func offlineReconcilerUsesOfflineSpeakerLabelsWhenAvailable() async {
    let turns = [
        TranscriptTurn(
            speakerLabel: "Speaker A",
            text: "Thanks",
            timestamp: .now,
            isFinal: true,
            startTimeSeconds: 0,
            endTimeSeconds: 0.5,
            speakerMatchConfidence: 0.4,
            speakerLabelIsProvisional: true
        ),
    ]
    let provider = StubOfflineProvider(
        result: DiarizationResult(
            segments: [
                TimedSpeakerSegment(
                    speakerId: "speaker_2",
                    embedding: [],
                    startTimeSeconds: 0,
                    endTimeSeconds: 0.5,
                    qualityScore: 1
                ),
            ]
        )
    )
    let reconciler = OfflineDiarizationReconciler(
        provider: provider,
        tuning: .productionDefault
    )

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("offline-test.wav")
    FileManager.default.createFile(atPath: tempURL.path, contents: Data())
    let result = await reconciler.reconcile(turns: turns, audioURL: tempURL)
    try? FileManager.default.removeItem(at: tempURL)

    #expect(result.usedOfflineDiarization == true)
    #expect(result.turns.first?.speakerLabel == "Speaker B")
    #expect(result.turns.first?.speakerLabelIsProvisional == false)
}

@Test func offlineReconcilerFallsBackWhenOfflineProcessingFails() async {
    let turns = [
        TranscriptTurn(
            speakerLabel: "Speaker A",
            text: "Fallback",
            timestamp: .now,
            isFinal: true,
            startTimeSeconds: 0,
            endTimeSeconds: 0.5,
            speakerMatchConfidence: 0.4,
            speakerLabelIsProvisional: true
        ),
    ]
    let reconciler = OfflineDiarizationReconciler(
        provider: FailingOfflineProvider(),
        tuning: .productionDefault
    )

    let result = await reconciler.reconcile(turns: turns, audioURL: nil)

    #expect(result.usedOfflineDiarization == false)
    #expect(result.turns.first?.speakerLabelIsProvisional == false)
}

@Test func sessionAudioCaptureDeletesTemporaryFilesOnCleanup() async throws {
    let capture = SessionAudioCapture()
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
    buffer.frameLength = 1600

    try await capture.start(sessionID: UUID(), format: format)
    try await capture.append(buffer)
    let url = await capture.stop()
    #expect(url != nil)
    #expect(FileManager.default.fileExists(atPath: url!.path))

    try await capture.cleanup()

    #expect(FileManager.default.fileExists(atPath: url!.path) == false)
}
