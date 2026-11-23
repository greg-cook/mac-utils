// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExternalDisplayController",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "DisplayCore"),
        .target(name: "DisplayDDC", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "ExternalDisplayController", dependencies: ["DisplayCore", "DisplayDDC"]),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
    ]
)
