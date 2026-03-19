import AVFoundation
import Foundation

actor SessionAudioCapture {
    private var audioFile: AVAudioFile?
    private var outputURL: URL?

    func start(sessionID: UUID, format: AVAudioFormat) throws {
        try deleteTemporaryFileIfNeeded()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterviewPartnerTranscription", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("\(sessionID.uuidString).caf")
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        outputURL = fileURL
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let audioFile else { return }
        try audioFile.write(from: buffer)
    }

    func stop() -> URL? {
        let finalURL = outputURL
        audioFile = nil
        return finalURL
    }

    func cleanup() throws {
        try deleteTemporaryFileIfNeeded()
        audioFile = nil
        outputURL = nil
    }

    private func deleteTemporaryFileIfNeeded() throws {
        guard let outputURL, FileManager.default.fileExists(atPath: outputURL.path) else { return }
        try FileManager.default.removeItem(at: outputURL)
    }
}
