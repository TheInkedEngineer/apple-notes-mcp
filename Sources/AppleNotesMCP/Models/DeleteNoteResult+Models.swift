import Foundation

extension Models {
  /// Payload returned by `delete_note`.
  struct DeleteNoteResult: Codable, Sendable, Equatable {
    let id: String
    let deleted: Bool
  }
}

extension Models.DeleteNoteResult {
  /// Encodes deletion result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
