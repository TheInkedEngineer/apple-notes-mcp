import Foundation

extension Models {
  /// Canonical note payload returned by MCP tools.
  ///
  /// `body` is optional because `list_notes` returns metadata-only entries while
  /// read tools return body text only when requested.
  ///
  /// Body text representation depends on the tool/query (`plain` or `markdown`).
  struct Note: Codable, Sendable {
    let id: String
    let title: String
    let body: String?
    let folder: String
    let createdAt: String
    let modifiedAt: String
  }
}

extension Array where Element == Models.Note {
  /// Encodes notes to a stable JSON string for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "[]")
  }
}
