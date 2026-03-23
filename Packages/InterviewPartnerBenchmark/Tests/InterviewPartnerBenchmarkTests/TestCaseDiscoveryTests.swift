import Testing
import Foundation
@testable import InterviewPartnerBenchmark

@Suite("TestCaseDiscovery")
struct TestCaseDiscoveryTests {

    @Test("Discovers test case from directory with audio, transcript, and metadata")
    func discoversTestCaseFromValidDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestCaseDiscoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a test case directory
        let caseDir = tempDir.appendingPathComponent("my-test-case")
        try FileManager.default.createDirectory(at: caseDir, withIntermediateDirectories: true)

        // Create required files
        try Data().write(to: caseDir.appendingPathComponent("audio.mov"))
        try "Hello world".data(using: .utf8)!
            .write(to: caseDir.appendingPathComponent("transcript.txt"))

        let metadata = TestCaseMetadata(duration: 60, speakerCount: 2, description: "A test clip")
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: caseDir.appendingPathComponent("metadata.json"))

        // Discover test cases
        let discovery = TestCaseDiscovery()
        let testCases = try discovery.discover(in: tempDir)

        #expect(testCases.count == 1)
        let testCase = try #require(testCases.first)
        #expect(testCase.name == "my-test-case")
        #expect(testCase.audioPath.standardizedFileURL == caseDir.appendingPathComponent("audio.mov").standardizedFileURL)
        #expect(testCase.transcriptPath.standardizedFileURL == caseDir.appendingPathComponent("transcript.txt").standardizedFileURL)
        #expect(testCase.metadata.duration == 60)
        #expect(testCase.metadata.speakerCount == 2)
        #expect(testCase.metadata.description == "A test clip")
    }

    @Test("Skips directories missing required files")
    func skipsIncompleteDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestCaseDiscoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Directory with only audio (missing transcript and metadata)
        let incompleteDir = tempDir.appendingPathComponent("incomplete-case")
        try FileManager.default.createDirectory(at: incompleteDir, withIntermediateDirectories: true)
        try Data().write(to: incompleteDir.appendingPathComponent("audio.mov"))

        // A regular file (not a directory) should also be skipped
        try Data().write(to: tempDir.appendingPathComponent("not-a-directory.json"))

        let discovery = TestCaseDiscovery()
        let testCases = try discovery.discover(in: tempDir)

        #expect(testCases.isEmpty)
    }

    @Test("Discovers multiple test cases sorted by name")
    func discoversMultipleSorted() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestCaseDiscoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = TestCaseMetadata(duration: 30, speakerCount: 1, description: "test")
        let metadataData = try JSONEncoder().encode(metadata)

        for name in ["zebra-case", "alpha-case", "middle-case"] {
            let caseDir = tempDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: caseDir, withIntermediateDirectories: true)
            try Data().write(to: caseDir.appendingPathComponent("audio.mov"))
            try "text".data(using: .utf8)!.write(to: caseDir.appendingPathComponent("transcript.txt"))
            try metadataData.write(to: caseDir.appendingPathComponent("metadata.json"))
        }

        let discovery = TestCaseDiscovery()
        let testCases = try discovery.discover(in: tempDir)

        #expect(testCases.count == 3)
        #expect(testCases[0].name == "alpha-case")
        #expect(testCases[1].name == "middle-case")
        #expect(testCases[2].name == "zebra-case")
    }
}
