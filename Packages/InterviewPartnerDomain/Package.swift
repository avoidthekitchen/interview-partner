// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "InterviewPartnerDomain",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "InterviewPartnerDomain",
            targets: ["InterviewPartnerDomain"]
        ),
    ],
    targets: [
        .target(
            name: "InterviewPartnerDomain"
        ),
        .testTarget(
            name: "InterviewPartnerDomainTests",
            dependencies: ["InterviewPartnerDomain"]
        ),
    ]
)
