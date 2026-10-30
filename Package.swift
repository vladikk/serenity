// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Serenity",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Serenity",
            path: "Sources/Serenity",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
