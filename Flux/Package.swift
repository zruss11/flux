// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Flux",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Flux",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
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
