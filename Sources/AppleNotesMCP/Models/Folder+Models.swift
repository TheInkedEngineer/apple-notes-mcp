import Foundation

extension Models {
  /// Canonical folder payload returned by `list_folders`.
  ///
  /// `path` is the authoritative nested path.
  /// Other fields are convenience projections for clients/agents.
  struct Folder: Codable, Sendable {
    let account: String
    let path: String
    let name: String
    let parentPath: String
    let depth: Int
  }
}

extension Array where Element == Models.Folder {
  /// Encodes folders to a stable JSON string for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "[]")
  }
}
