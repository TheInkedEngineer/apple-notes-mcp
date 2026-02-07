import Foundation

extension Models {
  /// Per-ID failure row for `batch_delete_notes`.
  struct BatchDeleteFailure: Codable, Sendable, Equatable {
    let id: String
    let reason: String
  }

  /// Payload returned by `batch_delete_notes`.
  struct BatchDeleteNotesResult: Codable, Sendable, Equatable {
    let deletedIDs: [String]
    let missingIDs: [String]
    let failed: [BatchDeleteFailure]
  }
}

extension Models.BatchDeleteNotesResult {
  /// Encodes batch-delete result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
