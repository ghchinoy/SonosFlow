// swift-tools-version: 5.9
// SonosFlow - Standalone macOS Sonos Controller powered by homectl MCP

import PackageDescription

let package = Package(
    name: "SonosFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SonosFlowSpike", targets: ["SonosFlowSpike"]),
        .executable(name: "SonosFlow", targets: ["SonosFlow"]),
        .library(name: "SonosFlowKit", targets: ["SonosFlowKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SonosFlowKit",
            path: "Sources/SonosFlowKit"
        ),
        .executableTarget(
            name: "SonosFlowSpike",
            dependencies: ["SonosFlowKit"],
            path: "Sources/SonosFlowSpike"
        ),
        .executableTarget(
            name: "SonosFlow",
            dependencies: ["SonosFlowKit"],
            path: "Sources/SonosFlow"
        ),
        .testTarget(
            name: "SonosFlowTests",
            dependencies: ["SonosFlowKit"],
            path: "Tests/SonosFlowTests"
        )
    ]
)
