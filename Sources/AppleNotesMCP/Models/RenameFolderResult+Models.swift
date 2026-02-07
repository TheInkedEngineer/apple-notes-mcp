import Foundation

extension Models {
  /// Payload returned by `rename_folder`.
  struct RenameFolderResult: Codable, Sendable, Equatable {
    /// Resolved account name.
    let account: String
    /// Source path before rename.
    let oldPath: String
    /// Path after rename.
    let newPath: String
    /// Leaf folder name after rename.
    let name: String
    /// Parent path, empty string for top-level folders.
    let parentPath: String
    /// Nesting depth (`0` for top-level folders).
    let depth: Int
    /// True when folder name was changed.
    let renamed: Bool
  }
}

extension Models.RenameFolderResult {
  /// Encodes rename-folder result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
