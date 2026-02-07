// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "apple-notes-mcp",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "apple-notes-mcp", targets: ["AppleNotesMCP"])
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.10.2"),
    .package(url: "https://github.com/apple/swift-markdown.git", from: "0.6.0")
  ],
  targets: [
    .executableTarget(
      name: "AppleNotesMCP",
      dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Markdown", package: "swift-markdown")
      ]
    ),
    .target(
      name: "AppleNotesMCPTestSupport",
      dependencies: [
        .product(name: "MCP", package: "swift-sdk")
      ],
      path: "Tests/TestSupport"
    ),
    .testTarget(
      name: "AppleNotesMCPTests",
      dependencies: [
        "AppleNotesMCP",
        "AppleNotesMCPTestSupport",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Markdown", package: "swift-markdown")
      ]
    ),
    .testTarget(
      name: "AppleNotesMCPIntegrationTests",
      dependencies: [
        "AppleNotesMCP",
        "AppleNotesMCPTestSupport",
        .product(name: "MCP", package: "swift-sdk")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
