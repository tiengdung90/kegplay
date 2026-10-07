// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kegplay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Kegplay", path: "Sources/Kegplay")
    ]
)
