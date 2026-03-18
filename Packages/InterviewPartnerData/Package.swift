// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "InterviewPartnerData",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "InterviewPartnerData",
            targets: ["InterviewPartnerData"]
        ),
    ],
    dependencies: [
        .package(path: "../InterviewPartnerDomain"),
    ],
    targets: [
        .target(
            name: "InterviewPartnerData",
            dependencies: ["InterviewPartnerDomain"]
        ),
        .testTarget(
            name: "InterviewPartnerDataTests",
            dependencies: ["InterviewPartnerData", "InterviewPartnerDomain"]
        ),
    ]
)
