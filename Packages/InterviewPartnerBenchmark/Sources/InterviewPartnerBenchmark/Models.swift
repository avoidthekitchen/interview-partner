import Foundation

/// Metadata about a test case, loaded from metadata.json.
public struct TestCaseMetadata: Sendable, Codable, Equatable {
    public let duration: Int
    public let speakerCount: Int
    public let description: String

    public init(duration: Int, speakerCount: Int, description: String) {
        self.duration = duration
        self.speakerCount = speakerCount
        self.description = description
    }
}

/// A discovered test case with paths to its audio, transcript, and metadata.
public struct TestCase: Sendable {
    public let name: String
    public let audioPath: URL
    public let transcriptPath: URL
    public let metadata: TestCaseMetadata

    public init(name: String, audioPath: URL, transcriptPath: URL, metadata: TestCaseMetadata) {
        self.name = name
        self.audioPath = audioPath
        self.transcriptPath = transcriptPath
        self.metadata = metadata
    }
}

/// The result of a single benchmark run for one test case.
public struct BenchmarkResult: Sendable, Codable, Equatable {
    public let testCaseName: String
    public let werAccuracy: Double
    public let diarizationAccuracy: Double

    public init(testCaseName: String, werAccuracy: Double, diarizationAccuracy: Double) {
        self.testCaseName = testCaseName
        self.werAccuracy = werAccuracy
        self.diarizationAccuracy = diarizationAccuracy
    }
}

/// Baseline metrics for all test cases, stored as JSON.
public struct BaselineMetrics: Sendable, Codable, Equatable {
    public var results: [String: CaseBaseline]

    public init(results: [String: CaseBaseline] = [:]) {
        self.results = results
    }
}

/// Baseline accuracy values for a single test case.
public struct CaseBaseline: Sendable, Codable, Equatable {
    public let werAccuracy: Double
    public let diarizationAccuracy: Double

    public init(werAccuracy: Double, diarizationAccuracy: Double) {
        self.werAccuracy = werAccuracy
        self.diarizationAccuracy = diarizationAccuracy
    }
}
