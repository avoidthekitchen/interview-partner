import AVFoundation
import Foundation
import Testing

@testable import InterviewPartnerServices

/// Smoke tests for ``FileAudioReplayer``.
///
/// These tests verify that the replayer can open an audio file and deliver
/// PCM buffers at approximately real-time rate. They do **not** require
/// FluidAudio models, so they should pass in any environment that has
/// AVFoundation available.
@Suite("FileAudioReplayer")
struct FileAudioReplayerTests {

    /// Returns the URL to the shared test audio clip.
    ///
    /// The file lives outside the package at the repo root under
    /// `tests/test-data/test-audio-clip/audio.mov`. We resolve the
    /// path relative to the source file location so it works for both
    /// `swift test` and Xcode.
    private static var testAudioURL: URL {
        // #filePath gives us the absolute path of this source file.
        // Walk up from Tests/InterviewPartnerServicesTests/ -> Packages/InterviewPartnerServices/ -> Packages/ -> repo root
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // remove FileAudioReplayerTests.swift
            .deletingLastPathComponent() // remove InterviewPartnerServicesTests
            .deletingLastPathComponent() // remove Tests
            .deletingLastPathComponent() // remove InterviewPartnerServices
            .deletingLastPathComponent() // remove Packages
        return repoRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("test-data")
            .appendingPathComponent("test-audio-clip")
            .appendingPathComponent("audio.mov")
    }

    @Test("Replayer delivers non-zero buffers from test audio file")
    func deliversBuffers() async throws {
        let audioURL = Self.testAudioURL
        try #require(
            FileManager.default.fileExists(atPath: audioURL.path),
            "Test audio file missing at \(audioURL.path)"
        )

        let replayer = FileAudioReplayer(fileURL: audioURL)

        // Use an actor to safely accumulate buffer stats from
        // the callback, which fires on an arbitrary thread.
        let stats = BufferStats()

        try replayer.start { buffer in
            let frames = buffer.frameLength
            Task {
                await stats.record(frameLength: frames)
            }
        }

        // Let the replayer run for a few seconds -- at real-time rate this
        // should produce many buffers from a 73-second clip.
        try await Task.sleep(for: .seconds(3))
        replayer.stop()

        let count = await stats.bufferCount
        let totalFrames = await stats.totalFrames
        #expect(count > 0, "Expected at least one buffer to be delivered")
        #expect(totalFrames > 0, "Expected non-zero total frames")
    }

    @Test("Replayer audioFormat reflects the file format after start")
    func audioFormatMatchesFile() async throws {
        let audioURL = Self.testAudioURL
        try #require(
            FileManager.default.fileExists(atPath: audioURL.path),
            "Test audio file missing at \(audioURL.path)"
        )

        let replayer = FileAudioReplayer(fileURL: audioURL)

        try replayer.start { _ in }
        let format = replayer.audioFormat

        // The format should be valid with a positive sample rate and at
        // least one channel.
        #expect(format.sampleRate > 0)
        #expect(format.channelCount >= 1)

        replayer.stop()
    }

    @Test("Replayer delivers buffers at approximately real-time rate")
    func realTimePacing() async throws {
        let audioURL = Self.testAudioURL
        try #require(
            FileManager.default.fileExists(atPath: audioURL.path),
            "Test audio file missing at \(audioURL.path)"
        )

        let replayer = FileAudioReplayer(fileURL: audioURL)
        let stats = BufferStats()

        try replayer.start { buffer in
            let frames = buffer.frameLength
            Task {
                await stats.record(frameLength: frames)
            }
        }

        try await Task.sleep(for: .seconds(2))
        replayer.stop()

        let count = await stats.bufferCount
        let totalFrames = await stats.totalFrames
        let format = replayer.audioFormat

        // Calculate how much audio was delivered.
        let deliveredSeconds = Double(totalFrames) / format.sampleRate

        // Allow generous tolerance -- real-time pacing should produce
        // roughly 2 seconds of audio in 2 wall-clock seconds, but Task.sleep
        // granularity and scheduling mean it could be anywhere from 1.0 to 3.0.
        #expect(count > 0, "Expected buffers to be delivered")
        #expect(
            deliveredSeconds > 0.5 && deliveredSeconds < 4.0,
            "Expected ~2s of audio but got \(deliveredSeconds)s"
        )
    }

    @Test("Replayer with format conversion delivers buffers")
    func formatConversion() async throws {
        let audioURL = Self.testAudioURL
        try #require(
            FileManager.default.fileExists(atPath: audioURL.path),
            "Test audio file missing at \(audioURL.path)"
        )

        // Request 16 kHz output, which is what the diarization engine
        // typically resamples to internally.
        let replayer = FileAudioReplayer(
            fileURL: audioURL,
            outputSampleRate: 16_000
        )
        let stats = BufferStats()

        try replayer.start { buffer in
            let frames = buffer.frameLength
            Task {
                await stats.record(frameLength: frames)
            }
        }

        try await Task.sleep(for: .seconds(2))
        replayer.stop()

        let count = await stats.bufferCount
        #expect(count > 0, "Expected buffers after format conversion")
        #expect(
            replayer.audioFormat.sampleRate == 16_000,
            "Expected 16 kHz output sample rate"
        )
    }

    @Test("Replayer stop cancels delivery")
    func stopCancelsDelivery() async throws {
        let audioURL = Self.testAudioURL
        try #require(
            FileManager.default.fileExists(atPath: audioURL.path),
            "Test audio file missing at \(audioURL.path)"
        )

        let replayer = FileAudioReplayer(fileURL: audioURL)
        let stats = BufferStats()

        try replayer.start { buffer in
            let frames = buffer.frameLength
            Task {
                await stats.record(frameLength: frames)
            }
        }

        // Let a few buffers come through then stop.
        try await Task.sleep(for: .seconds(1))
        replayer.stop()

        let countAfterStop = await stats.bufferCount

        // Wait another second -- no new buffers should arrive.
        try await Task.sleep(for: .seconds(1))
        let countLater = await stats.bufferCount

        // Allow a tiny margin for in-flight buffers at stop time.
        #expect(
            countLater - countAfterStop <= 2,
            "Expected no significant buffer delivery after stop"
        )
    }
}

// MARK: - Helpers

/// Thread-safe accumulator for buffer delivery statistics.
private actor BufferStats {
    var bufferCount: Int = 0
    var totalFrames: UInt64 = 0

    func record(frameLength: AVAudioFrameCount) {
        bufferCount += 1
        totalFrames += UInt64(frameLength)
    }
}
