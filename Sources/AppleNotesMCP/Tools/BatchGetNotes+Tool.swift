import Foundation
import MCP

extension Tool {
  /// `batch_get_notes` fetches multiple notes by IDs in one request.
  struct BatchGetNotes: Blueprint {

    // MARK: Properties

    static let name: String = "batch_get_notes"

    static let description: String = "Retrieve multiple Apple Notes by ID in one call. Returns found notes plus missingIDs. Supports plain, markdown, or raw-html body output."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "ids": .object([
          "type": "array",
          "items": .object(["type": "string"]),
          "description": "Required array of Apple Notes identifiers."
        ]),
        "bodyFormat": .object([
          "type": "string",
          "enum": .array([.string("plain"), .string("markdown"), .string("html")]),
          "description": "Body output format. Defaults to plain. Use 'html' for raw Notes body HTML."
        ])
      ]),
      "required": .array([.string("ids")]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting
    private let idBatchSize: Int

    /// Injects script factory and chunk size.
    ///
    /// `idBatchSize` is testable so suites can verify chunk/cancellation
    /// behavior deterministically.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      },
      idBatchSize: Int = 100
    ) {
      self.appleScriptFactory = appleScriptFactory
      self.idBatchSize = max(1, idBatchSize)
    }

    // MARK: Functions

    /// Fetches many notes by ID with partial-success semantics.
    ///
    /// Missing IDs are returned in `missingIDs` and do not fail the entire call.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      try Task.checkCancellation()
      let ids = try Self.parseIDs(arguments: params.arguments)
      let bodyFormat = try Self.parseBodyFormat(arguments: params.arguments)

      var notesByID: [String: Models.Note] = [:]
      var missingIDs = Set<String>()

      for chunk in ids.chunked(into: idBatchSize) {
        try Task.checkCancellation()
        let script = Self.script(ids: chunk)
        let executor = appleScriptFactory(script)

        let chunkResult = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsed = descriptor.parseBatchNoteLookupResult() else {
            throw Error.BatchGetNotes.invalidScriptResponse
          }
          return parsed
        }
        try Task.checkCancellation()

        for note in chunkResult.notes {
          notesByID[note.id] = note
        }

        for missingID in chunkResult.missingIDs {
          missingIDs.insert(missingID)
        }
      }

      let notes = ids.compactMap { id in
        notesByID[id].map { Self.formatBody($0, as: bodyFormat) }
      }
      let orderedMissingIDs = ids.filter { id in
        missingIDs.contains(id) && notesByID[id] == nil
      }

      let payload = try Models.BatchGetNotesResult(
        notes: notes,
        missingIDs: orderedMissingIDs
      ).mcpPayload()

      return .init(content: [.text(payload)], isError: false)
    }

    // MARK: Parsing

    /// Parses and validates requested note IDs.
    ///
    /// Keeps first-occurrence order while removing duplicates.
    private static func parseIDs(arguments: [String: MCP.Value]?) throws(Error.BatchGetNotes) -> [String] {
      guard let rawIDs = arguments?["ids"] else {
        throw .missingIDs
      }
      guard let inputIDs = rawIDs.arrayValue else {
        throw .invalidIDsType
      }
      guard !inputIDs.isEmpty else {
        throw .emptyIDs
      }

      var ids: [String] = []
      ids.reserveCapacity(inputIDs.count)

      var seen = Set<String>()
      for (index, value) in inputIDs.enumerated() {
        guard let rawID = value.stringValue else {
          throw .invalidIDElementType(index: index)
        }

        let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
          throw .emptyID(index: index)
        }

        if seen.insert(trimmedID).inserted {
          ids.append(trimmedID)
        }
      }

      guard !ids.isEmpty else {
        throw .emptyIDs
      }

      return ids
    }

    /// Parses output body format.
    private static func parseBodyFormat(arguments: [String: MCP.Value]?) throws(Error.BatchGetNotes) -> BodyOutputFormat {
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

    /// Formats returned note bodies for the requested output format.
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

    // MARK: Script

    /// Builds batch lookup script for a chunk of IDs.
    ///
    /// Uses structured per-ID rows so parser can split found vs missing safely.
    private static func script(ids: [String]) -> String {
      let idsLiteral = ids.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set requestedIDs to {\(idsLiteral)}
          set foundRows to {}
          set missingIDs to {}

          repeat with requestedID in requestedIDs
              set noteID to requestedID as string
              try
                  set n to first note whose id is noteID
                  set theID to id of n as string
                  set theTitle to name of n as string
                  set theBody to body of n as string
                  set theCreated to creation date of n
                  set theModified to modification date of n
                  set theFolder to ""
                  try
                      set theFolder to name of (container of n) as string
                  end try
                  set end of foundRows to {theID, theTitle, theBody, theCreated, theModified, theFolder}
              on error
                  set end of missingIDs to noteID
              end try
          end repeat

          return {foundRows, missingIDs}
      end tell
      """
    }
  }
}
