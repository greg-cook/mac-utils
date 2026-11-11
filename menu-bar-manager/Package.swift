// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MenuBarManager",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MenuBarRestriction"),
        .executableTarget(name: "MenuBarManager", dependencies: ["MenuBarRestriction"]),
    ]
)
