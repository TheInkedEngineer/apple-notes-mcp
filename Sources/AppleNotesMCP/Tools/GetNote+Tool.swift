import Foundation
import MCP

extension Tool {
  /// `get_note` returns a single note (including body) for a provided note ID.
  struct GetNote: Blueprint {

    // MARK: Properties

    static let name: String = "get_note"

    static let description: String = "Retrieve a single Apple Note by ID with full body content. Use bodyFormat='plain', 'markdown', or 'html' (raw Notes HTML)."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "id": .object([
          "type": "string",
          "description": "The unique Apple Notes identifier."
        ]),
        "bodyFormat": .object([
          "type": "string",
          "enum": .array([.string("plain"), .string("markdown"), .string("html")]),
          "description": "Body output format. Defaults to plain. Use 'html' for raw Notes body HTML."
        ])
      ]),
      "required": .array([.string("id")]),
      "additionalProperties": false
    ])

    /// Factory seam used by tests to inject deterministic AppleScript behavior.
    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects script factory.
    ///
    /// Production builds dynamic one-note scripts from ID; tests inject static
    /// descriptors for deterministic behavior.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Fetches one note by ID and formats body according to `bodyFormat`.
    ///
    /// Edge cases:
    /// - note-not-found maps to typed error via structured script prefix.
    /// - invalid descriptor shape is surfaced as `invalidScriptResponse`.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let noteID = try Self.parseNoteID(arguments: params.arguments)
      let bodyFormat = try Self.parseBodyFormat(arguments: params.arguments)
      let source = Self.script(noteID: noteID)
      let executor = appleScriptFactory(source)

      do {
        let note = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsedNote = descriptor.parseSingleNote() else {
            throw Error.GetNote.invalidScriptResponse
          }
          return parsedNote
        }

        let formattedNote = Self.formatBody(note, as: bodyFormat)
        let payload = try [formattedNote].mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.GetNote {
        throw error
      } catch {
        if let missingID = NoteScriptErrorMapper.noteNotFoundID(from: error) {
          throw Error.GetNote.noteNotFound(missingID)
        }
        throw error
      }
    }

    /// Validates and extracts the required note ID parameter.
    /// Parses required note ID using shared argument parsing helper.
    private static func parseNoteID(arguments: [String: MCP.Value]?) throws(Error.GetNote) -> String {
      try ToolArgumentParsing.parseRequiredNoteID(
        arguments: arguments,
        missing: Error.GetNote.missingID,
        invalidType: Error.GetNote.invalidIDType,
        empty: Error.GetNote.emptyID
      )
    }

    /// Parses output body format selection.
    ///
    /// Defaults to `.plain` to keep responses lightweight and searchable.
    private static func parseBodyFormat(arguments: [String: MCP.Value]?) throws(Error.GetNote) -> BodyOutputFormat {
      guard let rawFormat = arguments?["bodyFormat"] else {
        return .plain
      }
      guard let bodyFormatValue = rawFormat.stringValue else {
        throw .invalidBodyFormatType
      }
      guard let bodyFormat = BodyOutputFormat(rawValue: bodyFormatValue) else {
        throw .invalidBodyFormatValue(bodyFormatValue)
      }
      return bodyFormat
    }

    /// Formats body output while preserving metadata as-is.
    private static func formatBody(_ note: Models.Note, as format: BodyOutputFormat) -> Models.Note {
      guard let bodyHTML = note.body else {
        return note
      }
      let outputBody = BodyFormatter.formatStoredBodyForOutput(
        bodyHTML: bodyHTML,
        title: note.title,
        as: format
      )

      return Models.Note(
        id: note.id,
        title: note.title,
        body: outputBody,
        folder: note.folder,
        createdAt: note.createdAt,
        modifiedAt: note.modifiedAt
      )
    }

    /// Builds a focused AppleScript query for one note ID.
    /// Builds AppleScript source for one note lookup.
    ///
    /// Includes structured not-found prefix to keep mapper logic locale-safe.
    private static func script(noteID: String) -> String {
      let escapedID = noteID.escapedForAppleScriptLiteral()
      return """
      tell application "Notes"
          set noteID to "\(escapedID)"
          try
              set n to first note whose id is noteID
              set theId to id of n as string
              set theName to name of n as string
              set theBody to body of n as string
              set theCreated to creation date of n
              set theModified to modification date of n
              set theFolderName to ""
              try
                  set theFolderName to name of (container of n) as string
              end try
              return {theId, theName, theBody, theCreated, theModified, theFolderName}
          on error
              error "\(NoteScriptErrorPrefix.noteNotFound)" & noteID
          end try
      end tell
      """
    }
  }
}
