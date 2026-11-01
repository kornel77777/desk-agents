// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeskAgents",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DeskAgents", path: "Sources/DeskAgents")
    ]
)
