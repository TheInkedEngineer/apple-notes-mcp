import Foundation
import MCP

extension Tool {
  /// `update_note` updates an existing note's title/body and returns the updated note.
  ///
  /// This tool intentionally does not move notes. Use `move_note` for relocation.
  struct UpdateNote: Blueprint {

    // MARK: Properties

    static let name: String = "update_note"

    static let description: String = "Update an Apple Note's title and/or body by ID. Supports body modes (replace, append, prepend) and plain/html/markdown input. Does not move notes; use move_note for relocation."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "id": .object([
          "type": "string",
          "description": "The unique Apple Notes identifier."
        ]),
        "title": .object([
          "type": "string",
          "description": "Optional new title."
        ]),
        "body": .object([
          "type": "string",
          "description": "Optional new body content."
        ]),
        "bodyFormat": .object([
          "type": "string",
          "enum": .array([.string("plain"), .string("html"), .string("markdown")]),
          "description": "Input format for the body field. Defaults to plain."
        ]),
        "bodyMode": .object([
          "type": "string",
          "enum": .array([.string("replace"), .string("append"), .string("prepend")]),
          "description": "How body is applied when body is provided. Defaults to replace."
        ]),
        "outputBodyFormat": .object([
          "type": "string",
          "enum": .array([.string("plain"), .string("markdown"), .string("html")]),
          "description": "Response body format. Defaults to plain. Use html for raw Notes HTML."
        ])
      ]),
      "required": .array([.string("id")]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the script execution factory used for read and write phases.
    ///
    /// Tests use this seam to:
    /// - capture generated AppleScript sources
    /// - return deterministic descriptors for each phase
    /// - force specific script failures for error mapping assertions
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Executes update flow and returns the updated note.
    ///
    /// Design notes:
    /// - This tool performs two script calls for title/body updates:
    ///   1) read current note (for append/prepend and heading normalization)
    ///   2) write updated fields and read back canonical metadata
    /// - Folder moves are intentionally out of scope; `move_note` owns that behavior.
    /// - Cancellation is checked between phases so long-running requests can stop early.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let input = try Self.Input(arguments: params.arguments)
      try Task.checkCancellation()

      let currentNote = try await loadCurrentNote(noteID: input.id)
      try Task.checkCancellation()

      let effectiveTitle = input.title ?? currentNote.title
      let updatedBodyHTML = Self.buildUpdatedBodyHTML(from: currentNote, using: input, effectiveTitle: effectiveTitle)

      let writeSource = Self.writeScript(
        noteID: input.id,
        title: input.title,
        bodyHTML: updatedBodyHTML
      )
      let writeExecutor = appleScriptFactory(writeSource)

      do {
        let updatedNote = try await MainActor.run {
          let descriptor = try writeExecutor.run()
          guard let parsedNote = descriptor.parseSingleNote() else {
            throw Error.UpdateNote.invalidScriptResponse
          }
          return Self.formatBodyForOutput(parsedNote, as: input.outputBodyFormat)
        }

        let payload = try [updatedNote].mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.UpdateNote {
        throw error
      } catch {
        if let missingID = NoteScriptErrorMapper.noteNotFoundID(from: error) {
          throw Error.UpdateNote.noteNotFound(missingID)
        }
        throw error
      }
    }

    /// Loads current note snapshot by ID.
    ///
    /// The snapshot is required to:
    /// - preserve existing content when `bodyMode` is `append`/`prepend`
    /// - strip previously injected title heading before recomposition
    /// - provide current title when only body changes are requested
    private func loadCurrentNote(noteID: String) async throws -> Models.Note {
      let readSource = Self.readScript(noteID: noteID)
      let readExecutor = appleScriptFactory(readSource)

      do {
        return try await MainActor.run {
          let descriptor = try readExecutor.run()
          guard let parsedNote = descriptor.parseSingleNote() else {
            throw Error.UpdateNote.invalidScriptResponse
          }
          return parsedNote
        }
      } catch let error as Error.UpdateNote {
        throw error
      } catch {
        if let missingID = NoteScriptErrorMapper.noteNotFoundID(from: error) {
          throw Error.UpdateNote.noteNotFound(missingID)
        }
        throw error
      }
    }

    /// Builds final stored HTML body for the update operation.
    ///
    /// Rules:
    /// - returns `nil` only when neither title nor body is being updated
    /// - strips previously injected title heading from existing body first
    /// - recomposes body with the effective title heading to keep visual title in sync
    /// - honors body modes (`replace`, `append`, `prepend`) when body input exists
    private static func buildUpdatedBodyHTML(
      from currentNote: Models.Note,
      using input: Input,
      effectiveTitle: String
    ) -> String? {
      guard input.title != nil || input.body != nil else {
        return nil
      }

      let currentBodyHTML = currentNote.body ?? ""
      let existingLogicalBody = BodyFormatter.stripLeadingTitleHeading(
        from: currentBodyHTML,
        matching: currentNote.title
      )

      let nextLogicalBody: String
      if let bodyInput = input.body {
        let preparedBody = BodyFormatter.prepareForNotes(bodyInput, format: input.bodyFormat)
        switch input.bodyMode {
        case .replace:
          nextLogicalBody = preparedBody
        case .append:
          nextLogicalBody = combineBodySegments(first: existingLogicalBody, second: preparedBody)
        case .prepend:
          nextLogicalBody = combineBodySegments(first: preparedBody, second: existingLogicalBody)
        }
      } else {
        nextLogicalBody = existingLogicalBody
      }

      return BodyFormatter.composeStoredBodyHTML(title: effectiveTitle, preparedBody: nextLogicalBody)
    }

    /// Concatenates two prepared HTML body fragments with one visual blank line.
    ///
    /// Empty fragments are ignored so append/prepend never insert redundant separators.
    private static func combineBodySegments(first: String, second: String) -> String {
      let firstTrimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
      let secondTrimmed = second.trimmingCharacters(in: .whitespacesAndNewlines)

      if firstTrimmed.isEmpty {
        return second
      }
      if secondTrimmed.isEmpty {
        return first
      }

      return first + "<div><br></div>" + second
    }

    /// Formats stored HTML into the caller-requested response format.
    ///
    /// The parser provides raw stored HTML; this method is the tool edge where
    /// output format conversion is applied.
    private static func formatBodyForOutput(_ note: Models.Note, as format: BodyOutputFormat) -> Models.Note {
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

    // MARK: Script

    /// Generates read script used to fetch the current snapshot before mutation.
    ///
    /// Returns the canonical 6-field tuple consumed by `parseSingleNote()`.
    private static func readScript(noteID: String) -> String {
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

    /// Generates write script that applies title/body mutations and returns updated note.
    ///
    /// Update ordering is intentional:
    /// - body assignment runs before metadata `name` assignment
    /// - this mirrors create-note behavior that minimizes duplicate title artifacts
    private static func writeScript(noteID: String, title: String?, bodyHTML: String?) -> String {
      let escapedID = noteID.escapedForAppleScriptLiteral()

      var updateStatements: [String] = []
      // Keep body update before metadata name update. This mirrors the
      // create-note duplication fix pattern and avoids transient duplicate
      // heading/title states in Notes serialization.
      if let bodyHTML {
        updateStatements.append("set newBodyValue to \"\(bodyHTML.escapedForAppleScriptLiteral())\"")
        updateStatements.append("set body of n to newBodyValue")
      }
      if let title {
        updateStatements.append("set newTitleValue to \"\(title.escapedForAppleScriptLiteral())\"")
        updateStatements.append("set name of n to newTitleValue")
      }

      let updateBody = updateStatements.isEmpty ? "" : "\n          " + updateStatements.joined(separator: "\n          ")

      return """
      tell application "Notes"
          set noteID to "\(escapedID)"
          try
              set n to first note whose id is noteID\(updateBody)
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

extension Tool.UpdateNote {
  struct Input: Sendable {
    let id: String
    let title: String?
    let body: String?
    let bodyFormat: BodyInputFormat
    let bodyMode: BodyMode
    let outputBodyFormat: BodyOutputFormat

    /// Parses and validates `update_note` arguments.
    ///
    /// Contract:
    /// - `id` is required
    /// - at least one of `title` or `body` must be present
    /// - `bodyMode` is valid only when `body` is present
    init(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) {
      self.id = try Self.parseID(arguments: arguments)
      self.title = try Self.parseTitle(arguments: arguments)
      self.body = try Self.parseBody(arguments: arguments)
      self.bodyFormat = try Self.parseBodyFormat(arguments: arguments)
      self.bodyMode = try Self.parseBodyMode(arguments: arguments)
      self.outputBodyFormat = try Self.parseOutputBodyFormat(arguments: arguments)

      if title == nil, body == nil {
        throw .noChangesRequested
      }
      if body == nil, arguments?["bodyMode"] != nil {
        throw .bodyModeRequiresBody
      }
    }

    /// Parses required note ID.
    ///
    /// IDs are trimmed before emptiness validation to reject whitespace-only values.
    private static func parseID(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) -> String {
      guard let rawID = arguments?["id"] else {
        throw .missingID
      }
      guard let id = rawID.stringValue else {
        throw .invalidIDType
      }
      let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw .emptyID
      }
      return trimmed
    }

    /// Parses optional title update.
    ///
    /// Title updates are trimmed and rejected when empty.
    private static func parseTitle(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) -> String? {
      guard let rawTitle = arguments?["title"] else {
        return nil
      }
      guard let title = rawTitle.stringValue else {
        throw .invalidTitleType
      }
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw .emptyTitle
      }
      return trimmed
    }

    /// Parses optional body update.
    ///
    /// Body is not trimmed to preserve caller-authored leading/trailing newlines.
    private static func parseBody(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) -> String? {
      guard let rawBody = arguments?["body"] else {
        return nil
      }
      guard let body = rawBody.stringValue else {
        throw .invalidBodyType
      }
      return body
    }

    /// Parses body input format. Defaults to `plain` when omitted.
    private static func parseBodyFormat(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) -> BodyInputFormat {
      guard let rawFormat = arguments?["bodyFormat"] else {
        return .plain
      }
      guard let formatValue = rawFormat.stringValue else {
        throw .invalidBodyFormatType
      }
      guard let format = BodyInputFormat(rawValue: formatValue) else {
        throw .invalidBodyFormatValue(formatValue)
      }
      return format
    }

    /// Parses body merge mode. Defaults to `replace`.
    private static func parseBodyMode(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) -> BodyMode {
      guard let rawMode = arguments?["bodyMode"] else {
        return .replace
      }
      guard let modeValue = rawMode.stringValue else {
        throw .invalidBodyModeType
      }
      guard let mode = BodyMode(rawValue: modeValue) else {
        throw .invalidBodyModeValue(modeValue)
      }
      return mode
    }

    /// Parses requested output body format. Defaults to `plain`.
    private static func parseOutputBodyFormat(arguments: [String: MCP.Value]?) throws(Error.UpdateNote) -> BodyOutputFormat {
      guard let rawFormat = arguments?["outputBodyFormat"] else {
        return .plain
      }
      guard let formatValue = rawFormat.stringValue else {
        throw .invalidOutputBodyFormatType
      }
      guard let format = BodyOutputFormat(rawValue: formatValue) else {
        throw .invalidOutputBodyFormatValue(formatValue)
      }
      return format
    }
  }

  enum BodyMode: String, Sendable {
    case replace
    case append
    case prepend
  }
}
