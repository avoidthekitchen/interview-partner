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
    ],
    targets: [
        .target(
            name: "InterviewPartnerServices",
            dependencies: [
                "InterviewPartnerDomain",
                "InterviewPartnerData",
            ]
        ),
    ]
)
