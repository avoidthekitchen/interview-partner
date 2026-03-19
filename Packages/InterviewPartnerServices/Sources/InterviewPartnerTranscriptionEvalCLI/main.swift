import Foundation
import InterviewPartnerServices

@main
struct InterviewPartnerTranscriptionEvalCLI {
    static func main() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        let fixtureSet = value(after: "--fixture-set", in: arguments) ?? "baseline"
        let outputPath = value(after: "--output", in: arguments)
        let variantName = value(after: "--variant", in: arguments) ?? "production_current"
        let compareBaselinePath = value(after: "--compare-baseline", in: arguments)
        let mode = value(after: "--mode", in: arguments) ?? "replay"

        let fixturesRoot = packageRoot()
            .appendingPathComponent("Tests/InterviewPartnerServicesTests/Resources/TranscriptionEval", isDirectory: true)
        let fixtures = try TranscriptionBenchmarkRunner.loadFixtures(
            at: fixturesRoot,
            fixtureSet: fixtureSet
        )
        let variant = variant(named: variantName)
        let report: TranscriptionBenchmarkReport
        switch mode {
        case "audio-integration":
            report = try await AudioIntegrationBenchmarkRunner.run(
                fixtures: fixtures,
                fixturesRoot: fixturesRoot,
                variant: variant
            )
        default:
            report = TranscriptionBenchmarkRunner.run(fixtures: fixtures, variant: variant)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let reportData = try encoder.encode(report)

        if let outputPath {
            let outputURL = URL(fileURLWithPath: outputPath, isDirectory: false)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try reportData.write(to: outputURL)

            if let compareBaselinePath {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let baselineURL = URL(fileURLWithPath: compareBaselinePath, isDirectory: false)
                let baseline = try decoder.decode(
                    TranscriptionBenchmarkReport.self,
                    from: Data(contentsOf: baselineURL)
                )
                let comparison = BenchmarkComparison.compare(
                    baseline: baseline,
                    candidate: report
                )
                let comparisonURL = outputURL
                    .deletingPathExtension()
                    .appendingPathExtension("comparison.json")
                try encoder.encode(comparison).write(to: comparisonURL)
            }
        } else {
            FileHandle.standardOutput.write(reportData)
        }
    }

    private static func variant(named name: String) -> ReplayBenchmarkVariant {
        switch name {
        case ReplayBenchmarkVariant.phase1Baseline.name:
            return .phase1Baseline
        case ReplayBenchmarkVariant.pinnedTuned.name:
            return .pinnedTuned
        default:
            return .productionCurrent
        }
    }

    private static func value(after flag: String, in arguments: ArraySlice<String>) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        return arguments[nextIndex]
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
