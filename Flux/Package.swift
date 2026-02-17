// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Flux",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Flux",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "MLXAudioVAD", package: "mlx-audio-swift")
            ],
            path: "Sources",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FluxTests",
            dependencies: ["Flux"],
            path: "Tests"
        )
    ]
)
