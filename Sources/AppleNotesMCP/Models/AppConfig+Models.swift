import Foundation

extension Models {
  /// Runtime configuration used to initialize MCP server metadata/capabilities.
  struct AppConfig: Sendable {
    let name: String
    let version: String
    let listChanged: Bool
  }
}

extension Models.AppConfig {
  static let defaultName = "apple-notes-mcp"
  static let defaultVersion = "0.1.0"
  static let defaultListChanged = false

  static let `default` = Self(
    name: defaultName,
    version: defaultVersion,
    listChanged: defaultListChanged
  )
}
