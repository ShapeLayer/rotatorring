// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rotatorring",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RotatorringCore", path: "core", exclude: ["tests", "CMakeLists.txt"], sources: ["src/rotatorring_core.c"], publicHeadersPath: "include"),
        .executableTarget(
            name: "Rotatorring",
            dependencies: ["RotatorringCore"],
            path: "apps/macos/Sources/Rotatorring",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "RotatorringTests", dependencies: ["Rotatorring"], path: "tests/macos/CoreInterop")
    ]
)
