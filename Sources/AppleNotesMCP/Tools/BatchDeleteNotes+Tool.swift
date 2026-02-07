import Foundation
import MCP

extension Tool {
  /// `batch_delete_notes` deletes multiple notes by ID in one request.
  ///
  /// Partial success is expected and reported explicitly:
  /// - `deletedIDs`: resolved IDs successfully deleted
  /// - `missingIDs`: requested IDs not found
  /// - `failed`: IDs found but not deletable with a reason
  struct BatchDeleteNotes: Blueprint {

    // MARK: Properties

    static let name: String = "batch_delete_notes"

    static let description: String = "Delete multiple Apple Notes by ID in one call. Returns partial results: deletedIDs, missingIDs, and failed rows with reasons."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "ids": .object([
          "type": "array",
          "items": .object(["type": "string"]),
          "description": "Required array of Apple Notes identifiers."
        ])
      ]),
      "required": .array([.string("ids")]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting
    private let idBatchSize: Int

    /// Injects script factory and processing chunk size.
    ///
    /// The chunk size is injectable for deterministic chunk/cancellation tests.
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

    /// Deletes note IDs in chunks and returns partial-success payload.
    ///
    /// Contract details:
    /// - IDs are deduplicated by first occurrence before execution.
    /// - `deletedIDs` are script-resolved IDs (mirrors `delete_note` semantics).
    /// - cancellation checkpoints run between chunks.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      try Task.checkCancellation()
      let ids = try Self.parseIDs(arguments: params.arguments)

      var deletedIDs: [String] = []
      var missingIDs = Set<String>()
      var failedByID: [String: Models.BatchDeleteFailure] = [:]

      for chunk in ids.chunked(into: idBatchSize) {
        try Task.checkCancellation()
        let script = Self.script(ids: chunk)
        let executor = appleScriptFactory(script)

        let chunkResult = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsed = descriptor.parseBatchDeleteResult() else {
            throw Error.BatchDeleteNotes.invalidScriptResponse
          }
          return parsed
        }
        try Task.checkCancellation()

        deletedIDs.append(contentsOf: chunkResult.deletedIDs)
        for missingID in chunkResult.missingIDs {
          missingIDs.insert(missingID)
        }
        for failed in chunkResult.failed {
          failedByID[failed.id] = failed
        }
      }

      let orderedMissingIDs = ids.filter { missingIDs.contains($0) }
      let orderedFailed = ids.compactMap { failedByID[$0] }

      let payload = try Models.BatchDeleteNotesResult(
        deletedIDs: deletedIDs,
        missingIDs: orderedMissingIDs,
        failed: orderedFailed
      ).mcpPayload()

      return .init(content: [.text(payload)], isError: false)
    }

    // MARK: Parsing

    /// Parses and validates requested note IDs.
    ///
    /// Keeps first-occurrence order while removing duplicates.
    private static func parseIDs(arguments: [String: MCP.Value]?) throws(Error.BatchDeleteNotes) -> [String] {
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

    // MARK: Script

    /// Builds chunk script that reports deleted, missing, and failed IDs.
    ///
    /// Row contracts:
    /// - `deletedIDs`: resolved note IDs deleted successfully
    /// - `missingIDs`: requested IDs not found
    /// - `failedRows`: `{resolvedID, reason}` for found-but-not-deletable notes
    private static func script(ids: [String]) -> String {
      let idsLiteral = ids.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set requestedIDs to {\(idsLiteral)}
          set deletedIDs to {}
          set missingIDs to {}
          set failedRows to {}

          repeat with requestedID in requestedIDs
              set noteID to requestedID as string
              try
                  set n to first note whose id is noteID
                  set resolvedID to id of n as string
              on error
                  set end of missingIDs to noteID
                  set resolvedID to ""
              end try

              if resolvedID is not "" then
                  try
                      delete n
                      set end of deletedIDs to resolvedID
                  on error errMsg number errNum
                      set reasonText to (errMsg as string) & " (code " & (errNum as string) & ")"
                      set end of failedRows to {resolvedID, reasonText}
                  end try
              end if
          end repeat

          return {deletedIDs, missingIDs, failedRows}
      end tell
      """
    }
  }
}
