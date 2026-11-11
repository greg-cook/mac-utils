// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MenuBarStats",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "DieSensors", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MenuBarStats", dependencies: ["DieSensors"]),
    ]
)
