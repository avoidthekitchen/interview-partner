// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "InterviewPartnerFeatures",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "InterviewPartnerFeatures",
            targets: ["InterviewPartnerFeatures"]
        ),
    ],
    dependencies: [
        .package(path: "../InterviewPartnerDomain"),
        .package(path: "../InterviewPartnerServices"),
    ],
    targets: [
        .target(
            name: "InterviewPartnerFeatures",
            dependencies: [
                "InterviewPartnerDomain",
                "InterviewPartnerServices",
            ]
        ),
    ]
)
