// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Framecast",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Framecast",
            path: "Sources/Framecast",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
