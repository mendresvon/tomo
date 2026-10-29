// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tomo",
    platforms: [.macOS(.v14)],
    targets: [
        // Timer logic with no UI, so it is easy to test.
        .target(name: "TomoCore"),
        // The app: floating panel, pet, settings, alerts, shortcuts.
        .executableTarget(name: "Tomo", dependencies: ["TomoCore"]),
        .testTarget(name: "TomoCoreTests", dependencies: ["TomoCore"]),
    ]
)
