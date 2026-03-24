import Foundation

/// Discovers test cases by scanning a directory for subdirectories
/// that contain the required audio, transcript, and metadata files.
public struct TestCaseDiscovery: Sendable {

    public init() {}

    /// Scans the given directory for test case subdirectories.
    ///
    /// Each valid test case directory must contain:
    /// - `audio.mov` or `audio.m4a` (the audio file)
    /// - `transcript.txt` (the reference transcript)
    /// - `metadata.json` (test case metadata)
    ///
    /// Subdirectories missing any required file are silently skipped.
    ///
    /// - Parameter directory: The root directory to scan.
    /// - Returns: An array of discovered test cases, sorted by name.
    public func discover(in directory: URL) throws -> [TestCase] {
        let fileManager = FileManager.default

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var testCases: [TestCase] = []

        for itemURL in contents {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else { continue }

            let audioPath = ["audio.mov", "audio.m4a"]
                .map { itemURL.appendingPathComponent($0) }
                .first { fileManager.fileExists(atPath: $0.path) }
            let transcriptPath = itemURL.appendingPathComponent("transcript.txt")
            let metadataPath = itemURL.appendingPathComponent("metadata.json")

            guard let audioPath,
                  fileManager.fileExists(atPath: transcriptPath.path),
                  fileManager.fileExists(atPath: metadataPath.path) else {
                continue
            }

            let metadataData = try Data(contentsOf: metadataPath)
            let metadata = try JSONDecoder().decode(TestCaseMetadata.self, from: metadataData)

            let testCase = TestCase(
                name: itemURL.lastPathComponent,
                audioPath: audioPath,
                transcriptPath: transcriptPath,
                metadata: metadata
            )
            testCases.append(testCase)
        }

        return testCases.sorted { $0.name < $1.name }
    }
}
