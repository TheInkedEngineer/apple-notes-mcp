import Foundation

extension Models {
  /// Payload returned by `create_folder`.
  struct CreateFolderResult: Codable, Sendable, Equatable {
    /// Resolved account name.
    let account: String
    /// Resolved full folder path.
    let path: String
    /// Resolved leaf folder name.
    let name: String
    /// Resolved parent path, empty string for top-level folders.
    let parentPath: String
    /// Nesting depth (`0` for top-level folders).
    let depth: Int
    /// True only when every segment already existed.
    let alreadyExisted: Bool
  }
}

extension Models.CreateFolderResult {
  /// Encodes create-folder result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
