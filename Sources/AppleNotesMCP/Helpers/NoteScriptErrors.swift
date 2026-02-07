import Foundation

/// Shared script prefix contract for note-lookup AppleScript errors.
enum NoteScriptErrorPrefix {
  static let noteNotFound = "MCP_NOTE_NOT_FOUND::"
}

enum NoteScriptErrorMapper {
  /// Extracts not-found note IDs from structured AppleScript errors.
  static func noteNotFoundID(from error: any Swift.Error) -> String? {
    guard let scriptError = error as? Error.AppleScript else {
      return nil
    }
    guard case let .custom(info) = scriptError else {
      return nil
    }
    return ScriptErrorPayload.extract(after: NoteScriptErrorPrefix.noteNotFound, in: info)
  }
}
