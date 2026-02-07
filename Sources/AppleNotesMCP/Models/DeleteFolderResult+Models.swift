import Foundation

extension Models {
  /// Payload returned by `delete_folder`.
  struct DeleteFolderResult: Codable, Sendable, Equatable {
    let account: String
    let path: String
    let folder: String
    let deleted: Bool
  }
}

extension Models.DeleteFolderResult {
  /// Encodes folder deletion result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
