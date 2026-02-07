import Foundation

extension Models {
  /// Payload returned by `move_note`.
  struct MoveNoteResult: Codable, Sendable, Equatable {
    /// Resolved note identifier after move.
    let id: String
    /// Best-effort note metadata title. Can be empty when Notes metadata `name` is empty.
    let title: String
    /// Destination account name.
    let account: String
    /// Destination full folder path.
    let path: String
    /// Destination leaf folder name.
    let folder: String
    /// Destination note modification timestamp (ISO8601 UTC).
    let modifiedAt: String
  }
}

extension Models.MoveNoteResult {
  /// Encodes move result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
