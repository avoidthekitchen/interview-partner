// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "InterviewPartnerBenchmark",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "InterviewPartnerBenchmark",
            targets: ["InterviewPartnerBenchmark"]
        ),
        .executable(
            name: "BenchmarkCLI",
            targets: ["BenchmarkCLI"]
        ),
    ],
    dependencies: [
        .package(path: "../InterviewPartnerServices"),
    ],
    targets: [
        .target(
            name: "InterviewPartnerBenchmark"
        ),
        .executableTarget(
            name: "BenchmarkCLI",
            dependencies: [
                "InterviewPartnerBenchmark",
                .product(name: "InterviewPartnerServices", package: "InterviewPartnerServices"),
            ]
        ),
        .testTarget(
            name: "InterviewPartnerBenchmarkTests",
            dependencies: ["InterviewPartnerBenchmark"]
        ),
    ]
)
