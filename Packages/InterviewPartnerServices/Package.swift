// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "InterviewPartnerServices",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "InterviewPartnerServices",
            targets: ["InterviewPartnerServices"]
        ),
    ],
    dependencies: [
        .package(path: "../InterviewPartnerDomain"),
        .package(path: "../InterviewPartnerData"),
        .package(path: "../InterviewPartnerBenchmark"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "9830ce835881c0d0d40f90aabfaae3a6da5bebfb"),
    ],
    targets: [
        .target(
            name: "InterviewPartnerServices",
            dependencies: [
                "InterviewPartnerDomain",
                "InterviewPartnerData",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(
            name: "InterviewPartnerServicesTests",
            dependencies: [
                "InterviewPartnerServices",
                "InterviewPartnerBenchmark",
            ]
        ),
    ]
)
