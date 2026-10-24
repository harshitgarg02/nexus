// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nexus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NexusCore"),
        .executableTarget(name: "Nexus", dependencies: ["NexusCore"]),
        .testTarget(name: "NexusCoreTests", dependencies: ["NexusCore"]),
    ]
)
