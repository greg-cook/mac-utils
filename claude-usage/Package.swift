// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "ClaudeUsage"),
    ]
)
