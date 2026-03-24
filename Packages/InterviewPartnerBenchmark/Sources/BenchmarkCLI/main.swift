import Foundation
import InterviewPartnerBenchmark
import InterviewPartnerServices
import InterviewPartnerDomain

// MARK: - CLI Entry Point

@main
@MainActor
struct BenchmarkCLI {
    static func main() async {
        let runner = BenchmarkRunner()
        await runner.run()
    }
}

// MARK: - CLI Implementation

@MainActor
private struct BenchmarkRunner {
    private let arguments: [String]
    private let fileManager = FileManager.default

    init() {
        self.arguments = Array(CommandLine.arguments.dropFirst())
    }

    func run() async {
        // Parse arguments
        let config = parseArguments()

        // Resolve paths
        let testDataURL = resolveTestDataPath(config.testDataPath)
        let baselineURL = config.baselinePath.map { URL(fileURLWithPath: $0) }
            ?? testDataURL.appendingPathComponent("baseline_metrics.json")

        // Check if test data exists
        guard fileManager.fileExists(atPath: testDataURL.path) else {
            printError("Test data directory not found: \(testDataURL.path)")
            exit(1)
        }

        // Discover test cases
        let discovery = TestCaseDiscovery()
        let testCases: [TestCase]
        do {
            testCases = try discovery.discover(in: testDataURL)
        } catch {
            printError("Failed to discover test cases: \(error)")
            exit(1)
        }

        guard !testCases.isEmpty else {
            printError("No test cases found in \(testDataURL.path)")
            exit(1)
        }

        // Run benchmarks
        var results: [TestCaseResult] = []
        var hasErrors = false

        for testCase in testCases {
            FileHandle.standardError.write("Running benchmark for: \(testCase.name)...\n")

            do {
                let result = try await runBenchmark(for: testCase)
                results.append(result)
            } catch {
                printError("Failed to run benchmark for \(testCase.name): \(error)")
                hasErrors = true
            }
        }

        // Compare against baseline
        let comparator = BaselineComparator(baselinePath: baselineURL)
        var comparisons: [TestCaseComparison] = []
        var hasRegression = false

        for result in results {
            do {
                let comparison = try comparator.compare(result: result.benchmarkResult)
                comparisons.append(TestCaseComparison(result: result, comparison: comparison))

                if comparison.isRegression {
                    hasRegression = true
                }

                // Update baseline if requested
                if config.updateBaseline {
                    try comparator.updateBaseline(with: result.benchmarkResult)
                }
            } catch {
                printError("Failed to compare baseline for \(result.testCase.name): \(error)")
                hasErrors = true
            }
        }

        // Output results
        if config.outputJSON {
            outputJSONReport(comparisons: comparisons, hasRegression: hasRegression)
        } else {
            outputTextReport(comparisons: comparisons, hasRegression: hasRegression)
        }

        // Exit with appropriate code
        if hasErrors || hasRegression {
            exit(1)
        }
    }

    // MARK: - Argument Parsing

    private struct CLIConfiguration {
        var outputJSON = false
        var updateBaseline = false
        var testDataPath: String?
        var baselinePath: String?
    }

    private func parseArguments() -> CLIConfiguration {
        var config = CLIConfiguration()
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]

            switch arg {
            case "--json":
                config.outputJSON = true
                index += 1

            case "--update-baseline":
                config.updateBaseline = true
                index += 1

            case "--test-data":
                if index + 1 < arguments.count {
                    config.testDataPath = arguments[index + 1]
                    index += 2
                } else {
                    printError("Missing value for --test-data")
                    exit(1)
                }

            case "--baseline":
                if index + 1 < arguments.count {
                    config.baselinePath = arguments[index + 1]
                    index += 2
                } else {
                    printError("Missing value for --baseline")
                    exit(1)
                }

            case "--help", "-h":
                printUsage()
                exit(0)

            default:
                printError("Unknown argument: \(arg)")
                printUsage()
                exit(1)
            }
        }

        return config
    }

    private func printUsage() {
        print("""
        Usage: BenchmarkCLI [options]

        Options:
          --json              Output results as JSON
          --update-baseline   Update the baseline with current results
          --test-data PATH    Path to test data directory (default: ../../tests/test-data)
          --baseline PATH     Path to baseline JSON file
          --help, -h          Show this help message

        Exit codes:
          0  Success (no regression)
          1  Error or regression detected
        """)
    }

    // MARK: - Path Resolution

    private func resolveTestDataPath(_ path: String?) -> URL {
        if let path = path {
            return URL(fileURLWithPath: path)
        }

        // Default: derive from this source file location
        // Sources/BenchmarkCLI/main.swift -> ../../../tests/test-data
        let sourcePath = URL(fileURLWithPath: #filePath)
        return sourcePath
            .deletingLastPathComponent() // BenchmarkCLI
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // InterviewPartnerBenchmark
            .deletingLastPathComponent() // Packages
            .appendingPathComponent("tests")
            .appendingPathComponent("test-data")
    }

    // MARK: - Benchmark Execution

    private func runBenchmark(for testCase: TestCase) async throws -> TestCaseResult {
        let replayer = FileAudioReplayer(fileURL: testCase.audioPath)
        let service = DefaultTranscriptionService(audioProvider: replayer)

        // Collect events
        let collector = TranscriptionEventCollector()
        service.setEventHandler { event in
            Task {
                await collector.handle(event)
            }
        }

        // Start session
        let sessionID = UUID()
        let startedAt = Date()

        do {
            try await service.start(sessionID: sessionID, startedAt: startedAt)
        } catch {
            throw BenchmarkError.transcriptionUnavailable(error)
        }

        // Wait for replay to complete
        let replayDuration = Double(testCase.metadata.duration)
        let waitSeconds = replayDuration + 5.0
        try await Task.sleep(for: .seconds(waitSeconds))

        // Stop and get results
        let stopResult = await service.stop()
        let collectedTurns = await collector.finalizedTurns
        let turns = stopResult.reconciledTurns.isEmpty ? collectedTurns : stopResult.reconciledTurns

        // Parse ground truth
        let groundTruthText = try String(contentsOf: testCase.transcriptPath, encoding: .utf8)
        let groundTruthTurns = GroundTruthParser.parse(groundTruthText)

        // Score WER
        let referenceText = groundTruthTurns
            .flatMap(\.words)
            .joined(separator: " ")
        let hypothesisText = turns
            .map(\.text)
            .joined(separator: " ")
        let werResult = WERScorer.score(reference: referenceText, hypothesis: hypothesisText)

        // Score diarization
        let referenceLabeledWords: [LabeledWord] = groundTruthTurns.flatMap { turn in
            turn.words.map { word in
                LabeledWord(word: word, speaker: turn.speaker)
            }
        }
        let hypothesisLabeledWords: [LabeledWord] = turns.flatMap { turn in
            turn.text
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { word in
                    LabeledWord(word: word, speaker: turn.speakerLabel)
                }
        }
        let diarizationResult = DiarizationScorer.score(
            reference: referenceLabeledWords,
            hypothesis: hypothesisLabeledWords
        )

        let benchmarkResult = BenchmarkResult(
            testCaseName: testCase.name,
            werAccuracy: werResult.accuracy,
            diarizationAccuracy: diarizationResult.accuracy
        )

        return TestCaseResult(
            testCase: testCase,
            benchmarkResult: benchmarkResult,
            werDetails: werResult,
            diarizationDetails: diarizationResult
        )
    }

    // MARK: - Output Formatting

    private func outputTextReport(comparisons: [TestCaseComparison], hasRegression: Bool) {
        print("\nTranscription & Diarization Benchmark Report")
        print("=" * 45)
        print()

        for comparison in comparisons {
            let result = comparison.result
            let baseline = comparison.comparison

            let wer = result.werDetails
            let dia = result.diarizationDetails
            print("Test Case: \(result.testCase.name)")
            print("  Duration: \(result.testCase.metadata.duration)s | Speakers: \(result.testCase.metadata.speakerCount)")
            print("  WER Accuracy:         \(String(format: "%.2f", result.benchmarkResult.werAccuracy))%  (sub:\(wer.substitutions) ins:\(wer.insertions) del:\(wer.deletions))")
            print("  Diarization Accuracy: \(String(format: "%.2f", result.benchmarkResult.diarizationAccuracy))%  (\(dia.correctWords)/\(dia.totalMatchedWords) words correct)")

            if let werDelta = baseline.werDelta {
                let sign = werDelta >= 0 ? "+" : ""
                let status = werDelta >= 0 ? "improved" : "regressed"
                print("  Baseline WER:         \(String(format: "%.2f", result.benchmarkResult.werAccuracy - werDelta))% (\(sign)\(String(format: "%.2f", werDelta))pp, \(status))")
            } else {
                print("  Baseline WER:         (no baseline)")
            }

            if let diarizationDelta = baseline.diarizationDelta {
                let sign = diarizationDelta >= 0 ? "+" : ""
                let status = diarizationDelta >= 0 ? "improved" : "regressed"
                print("  Baseline Diarization: \(String(format: "%.2f", result.benchmarkResult.diarizationAccuracy - diarizationDelta))% (\(sign)\(String(format: "%.2f", diarizationDelta))pp, \(status))")
            } else {
                print("  Baseline Diarization: (no baseline)")
            }
            print()
        }

        // Aggregate
        let avgWER = comparisons.map(\.result.benchmarkResult.werAccuracy).reduce(0, +) / Double(comparisons.count)
        let avgDiarization = comparisons.map(\.result.benchmarkResult.diarizationAccuracy).reduce(0, +) / Double(comparisons.count)
        let passed = comparisons.filter { !$0.comparison.isRegression }.count
        let regressed = comparisons.filter { $0.comparison.isRegression }.count

        print("Aggregate Results")
        print("-" * 17)
        print("  Average WER Accuracy:         \(String(format: "%.2f", avgWER))%")
        print("  Average Diarization Accuracy: \(String(format: "%.2f", avgDiarization))%")
        print("  Test Cases: \(comparisons.count) total, \(passed) passed, \(regressed) regressed")
        print()
        print("Result: \(hasRegression ? "FAIL (regression detected)" : "PASS")")
    }

    private func outputJSONReport(comparisons: [TestCaseComparison], hasRegression: Bool) {
        let report = JSONReport(
            testCases: comparisons.map { comp in
                JSONReport.TestCaseResult(
                    name: comp.result.testCase.name,
                    duration: comp.result.testCase.metadata.duration,
                    speakerCount: comp.result.testCase.metadata.speakerCount,
                    werAccuracy: comp.result.benchmarkResult.werAccuracy,
                    diarizationAccuracy: comp.result.benchmarkResult.diarizationAccuracy,
                    baselineWerAccuracy: comp.comparison.werDelta.map { comp.result.benchmarkResult.werAccuracy - $0 },
                    baselineDiarizationAccuracy: comp.comparison.diarizationDelta.map { comp.result.benchmarkResult.diarizationAccuracy - $0 },
                    regressed: comp.comparison.isRegression
                )
            },
            aggregate: JSONReport.Aggregate(
                averageWerAccuracy: comparisons.map(\.result.benchmarkResult.werAccuracy).reduce(0, +) / Double(comparisons.count),
                averageDiarizationAccuracy: comparisons.map(\.result.benchmarkResult.diarizationAccuracy).reduce(0, +) / Double(comparisons.count),
                totalCases: comparisons.count,
                passedCases: comparisons.filter { !$0.comparison.isRegression }.count,
                regressedCases: comparisons.filter { $0.comparison.isRegression }.count
            ),
            result: hasRegression ? "FAIL" : "PASS"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(report)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } catch {
            printError("Failed to encode JSON: \(error)")
            exit(1)
        }
    }

    // MARK: - Utilities

    private func printError(_ message: String) {
        FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
    }
}

// Helper extension for writing to stderr
private extension FileHandle {
    func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.write(data)
    }
}

// MARK: - Supporting Types

private struct TestCaseResult {
    let testCase: TestCase
    let benchmarkResult: BenchmarkResult
    let werDetails: WERResult
    let diarizationDetails: DiarizationResult
}

private struct TestCaseComparison {
    let result: TestCaseResult
    let comparison: InterviewPartnerBenchmark.ComparisonResult
}

private enum BenchmarkError: Error {
    case transcriptionUnavailable(Error)
}

private struct JSONReport: Codable {
    struct TestCaseResult: Codable {
        let name: String
        let duration: Int
        let speakerCount: Int
        let werAccuracy: Double
        let diarizationAccuracy: Double
        let baselineWerAccuracy: Double?
        let baselineDiarizationAccuracy: Double?
        let regressed: Bool
    }

    struct Aggregate: Codable {
        let averageWerAccuracy: Double
        let averageDiarizationAccuracy: Double
        let totalCases: Int
        let passedCases: Int
        let regressedCases: Int
    }

    let testCases: [TestCaseResult]
    let aggregate: Aggregate
    let result: String
}

// MARK: - String Helpers

private extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

// MARK: - Transcription Event Collector

private actor TranscriptionEventCollector {
    private(set) var finalizedTurns: [InterviewPartnerDomain.TranscriptTurn] = []

    func handle(_ event: TranscriptionServiceEvent) {
        switch event {
        case .finalizedTurn(let turn):
            finalizedTurns.append(turn)
        case .partialText, .transcriptGap, .diarizationSnapshot, .limitedModeChanged:
            break
        }
    }
}
