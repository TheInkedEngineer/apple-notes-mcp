import Foundation

extension Models {
  /// Individual note move failure within a `move_folder` orchestration.
  struct MoveFolderNoteFailure: Codable, Sendable, Equatable {
    let noteID: String
    let noteTitle: String
    let sourceFolder: String
    let destinationFolder: String
    let reason: String
  }
}

extension Models {
  /// Payload returned by `move_folder`.
  struct MoveFolderResult: Codable, Sendable, Equatable {
    /// Source account name before move.
    let sourceAccount: String
    /// Source path before move.
    let sourcePath: String
    /// Destination account name.
    let destinationAccount: String
    /// Final path after move.
    let destinationPath: String
    /// Leaf folder name that moved.
    let folder: String
    /// True when all notes were moved and source was deleted.
    let moved: Bool
    /// Number of notes successfully moved.
    let movedNoteCount: Int
    /// Notes that failed to move.
    let failedNoteMoves: [Models.MoveFolderNoteFailure]
    /// Folder paths that were newly created at the destination.
    let createdFolders: [String]
    /// True when the source folder tree was deleted after move.
    let sourceDeleted: Bool
    /// True when some notes moved but others failed.
    let partial: Bool
  }
}

extension Models.MoveFolderResult {
  /// Encodes move-folder result into JSON for MCP text responses.
  func mcpPayload() throws -> String {
    try PayloadEncoding.encodeToJSONString(self, fallback: "{}")
  }
}
