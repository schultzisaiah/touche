// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Touche",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Touche",
            path: "Sources/Touche",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ToucheTests",
            dependencies: ["Touche"],
            path: "Tests/ToucheTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
