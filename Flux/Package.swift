// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flux",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Flux",
            path: "Sources"
        )
    ]
)
