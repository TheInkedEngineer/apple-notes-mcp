import Foundation
import MCP

extension Tool {
  /// `delete_note` deletes one note identified by ID.
  struct DeleteNote: Blueprint {

    // MARK: Properties

    static let name: String = "delete_note"

    static let description: String = "Delete a single Apple Note by ID."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "id": .object([
          "type": "string",
          "description": "The unique Apple Notes identifier."
        ])
      ]),
      "required": .array([.string("id")]),
      "additionalProperties": false
    ])

    /// Factory seam used by tests to inject deterministic AppleScript behavior.
    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the script execution factory.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Deletes one note by ID.
    ///
    /// The script resolves ID first and returns it after deletion so callers can
    /// confirm which note instance was removed.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let noteID = try Self.parseNoteID(arguments: params.arguments)
      let source = Self.script(noteID: noteID)
      let executor = appleScriptFactory(source)

      do {
        let deletedID = try await MainActor.run {
          let descriptor = try executor.run()
          guard let resolvedID = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                !resolvedID.isEmpty else {
            throw Error.DeleteNote.invalidScriptResponse
          }
          return resolvedID
        }

        let payload = try Models.DeleteNoteResult(id: deletedID, deleted: true).mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.DeleteNote {
        throw error
      } catch {
        if let missingID = NoteScriptErrorMapper.noteNotFoundID(from: error) {
          throw Error.DeleteNote.noteNotFound(missingID)
        }
        throw error
      }
    }

    /// Validates and extracts the required note ID parameter.
    /// Parses required note ID with shared validation rules.
    private static func parseNoteID(arguments: [String: MCP.Value]?) throws(Error.DeleteNote) -> String {
      try ToolArgumentParsing.parseRequiredNoteID(
        arguments: arguments,
        missing: Error.DeleteNote.missingID,
        invalidType: Error.DeleteNote.invalidIDType,
        empty: Error.DeleteNote.emptyID
      )
    }

    /// Builds a focused AppleScript delete request for one note ID.
    /// Generates delete script with structured note-not-found prefix.
    private static func script(noteID: String) -> String {
      let escapedID = noteID.escapedForAppleScriptLiteral()
      return """
      tell application "Notes"
          set noteID to "\(escapedID)"
          try
              set n to first note whose id is noteID
              set resolvedID to id of n as string
          on error
              error "\(NoteScriptErrorPrefix.noteNotFound)" & noteID
          end try
          delete n
          return resolvedID
      end tell
      """
    }
  }
}
