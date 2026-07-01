// swift-tools-version: 5.9
import PackageDescription

// LiveDocs — primary-source-first "always latest docs" engine.
//
// Two targets:
//   • LiveDocsCore   — pure discovery logic + network layer (no MCP dependency,
//                      fully unit-testable; network is injected via HTTPClient).
//   • CheLiveDocsMCP — the MCP stdio server that exposes the engine as tools.
//
// Keeping the engine in a dependency-free library target is deliberate: the
// discovery IP (candidate generation, soft-404 classification, registry parsing,
// source ranking) is verified by `swift test` without spinning up the MCP SDK or
// touching the network. The executable is a thin transport shell over it.
let package = Package(
    name: "CheLiveDocsMCP",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        .target(
            name: "LiveDocsCore",
            path: "Sources/LiveDocsCore"
        ),
        .executableTarget(
            name: "CheLiveDocsMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                "LiveDocsCore"
            ],
            path: "Sources/CheLiveDocsMCP"
        ),
        .testTarget(
            name: "LiveDocsCoreTests",
            dependencies: ["LiveDocsCore"],
            path: "Tests/LiveDocsCoreTests"
        ),
        .testTarget(
            name: "CheLiveDocsMCPTests",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                "LiveDocsCore",
                "CheLiveDocsMCP"
            ],
            path: "Tests/CheLiveDocsMCPTests"
        )
    ]
)
