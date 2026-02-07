import Foundation
import MCP

/// Shared helpers for extracting common tool arguments with typed errors.
enum ToolArgumentParsing {
  /// Parses required `id` argument used by note-targeting tools.
  static func parseRequiredNoteID<E: Swift.Error>(
    arguments: [String: MCP.Value]?,
    missing: E,
    invalidType: E,
    empty: E
  ) throws(E) -> String {
    guard let rawID = arguments?["id"] else {
      throw missing
    }
    guard let noteID = rawID.stringValue else {
      throw invalidType
    }

    let trimmedID = noteID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedID.isEmpty else {
      throw empty
    }
    return trimmedID
  }
}
