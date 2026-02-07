import Foundation

extension Models {
  /// Payload returned by `batch_get_notes`.
  struct BatchGetNotesResult: Codable, Sendable {
    let notes: [Note]
    let missingIDs: [String]
  }
}

extension Models.BatchGetNotesResult {
  /// Encodes batch result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
