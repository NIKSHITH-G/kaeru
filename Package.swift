// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kaeru",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Kaeru", path: "Sources/Kaeru")
    ]
)
