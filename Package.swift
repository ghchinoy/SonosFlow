// swift-tools-version: 5.9
// SonosFlow - Standalone macOS Sonos Controller powered by homectl MCP

import PackageDescription

let strictConcurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
    name: "SonosFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SonosFlowSpike", targets: ["SonosFlowSpike"]),
        .executable(name: "SonosOfficialMCPSpike", targets: ["SonosOfficialMCPSpike"]),
        .executable(name: "SonosFlow", targets: ["SonosFlow"]),
        .library(name: "SonosFlowKit", targets: ["SonosFlowKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SonosFlowKit",
            path: "Sources/SonosFlowKit",
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "SonosFlowSpike",
            dependencies: ["SonosFlowKit"],
            path: "Sources/SonosFlowSpike",
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "SonosOfficialMCPSpike",
            dependencies: ["SonosFlowKit"],
            path: "Sources/SonosOfficialMCPSpike",
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "SonosFlow",
            dependencies: ["SonosFlowKit"],
            path: "Sources/SonosFlow",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "SonosFlowTests",
            dependencies: ["SonosFlowKit"],
            path: "Tests/SonosFlowTests",
            swiftSettings: strictConcurrencySettings
        )
    ]
)
