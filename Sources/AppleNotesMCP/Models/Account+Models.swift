import Foundation

extension Models {
  /// Canonical account payload returned by `list_accounts`.
  struct Account: Codable, Sendable {
    let name: String
  }
}

extension Array where Element == Models.Account {
  /// Encodes accounts to a stable JSON string for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "[]")
  }
}
