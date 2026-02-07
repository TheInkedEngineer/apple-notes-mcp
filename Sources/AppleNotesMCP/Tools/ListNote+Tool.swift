import Foundation
import MCP

extension Tool {
  /// `list_notes` returns metadata and supports search/sort/pagination.
  ///
  /// Body content is fetched only when needed (`searchIn = body|all`) to keep
  /// metadata-only queries fast and predictable.
  struct ListNotes: Blueprint {

    // MARK: Properties

    static let name: String = "list_notes"

    static let description: String = "List Apple Notes metadata (id, title, folder, dates) with optional body retrieval and plain/markdown/raw-html body formatting."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "limit": .object([
          "type": "integer",
          "description": "Maximum number of notes to return. Use 0 for no limit."
        ]),
        "offset": .object([
          "type": "integer",
          "description": "Skip the first N matching notes. Requires limit > 0."
        ]),
        "searchText": .object([
          "type": "string",
          "description": "Text query used for title/body search."
        ]),
        "searchIn": .object([
          "type": "string",
          "enum": .array([.string("title"), .string("body"), .string("all")]),
          "description": "Search scope. Defaults to title when searchText is provided."
        ]),
        "account": .object([
          "type": "string",
          "description": "Optional account name scope (for example: iCloud, On My Mac). Case-sensitive."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Optional nested folder path scope using '/': 'Parent/Child'. Case-sensitive."
        ]),
        "includeBody": .object([
          "type": "boolean",
          "description": "Include note bodies in results. Reuses cached bodies from body searches when possible."
        ]),
        "bodyFormat": .object([
          "type": "string",
          "enum": .array([.string("plain"), .string("markdown"), .string("html")]),
          "description": "Body output format when includeBody is true. Defaults to plain. Use 'html' for raw Notes body HTML."
        ]),
        "orderBy": .object([
          "type": "string",
          "enum": .array([.string("modified"), .string("created")]),
          "description": "Sort field used when ordering notes."
        ]),
        "orderDirection": .object([
          "type": "string",
          "enum": .array([.string("recent"), .string("oldest")]),
          "description": "Sort direction. Defaults to recent when orderBy is provided."
        ]),
        "createdAfter": .object([
          "type": "string",
          "description": "ISO8601 date lower bound (inclusive) for creation date. Accepts: '2025-01-15T09:30:00.000Z', '2025-01-15T09:30:00Z', '2025-01-15T09:30:00+02:00', or '2025-01-15' (start of day UTC)."
        ]),
        "createdBefore": .object([
          "type": "string",
          "description": "ISO8601 date upper bound (inclusive) for creation date. Date-only input is treated as end of that day (23:59:59.999Z)."
        ]),
        "modifiedAfter": .object([
          "type": "string",
          "description": "ISO8601 date lower bound (inclusive) for modification date."
        ]),
        "modifiedBefore": .object([
          "type": "string",
          "description": "ISO8601 date upper bound (inclusive) for modification date. Date-only input is treated as end of that day (23:59:59.999Z)."
        ])
      ]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting
    /// Resolves note bodies for a batch of IDs as raw HTML.
    private let bodyLookup: @Sendable ([String]) async throws -> [String: String]
    /// Max IDs per body lookup batch.
    private let bodyBatchSize: Int

    /// Designated initializer for production and test injection.
    ///
    /// `bodyLookup` and `bodyBatchSize` are injectable to keep search/pagination
    /// behavior deterministic in tests.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      },
      bodyBatchSize: Int = 50,
      bodyLookup: @escaping @Sendable ([String]) async throws -> [String: String] = { noteIDs in
        try await Self.fetchBodies(for: noteIDs)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
      self.bodyBatchSize = max(1, bodyBatchSize)
      self.bodyLookup = bodyLookup
    }

    /// Convenience initializer for tests that use one static script executor.
    init(
      appleScriptExecutor: any AppleScriptExecuting,
      bodyBatchSize: Int = 50,
      bodyLookup: @escaping @Sendable ([String]) async throws -> [String: String] = { noteIDs in
        try await Self.fetchBodies(for: noteIDs)
      }
    ) {
      self.init(
        appleScriptFactory: { _ in appleScriptExecutor },
        bodyBatchSize: bodyBatchSize,
        bodyLookup: bodyLookup
      )
    }

    // MARK: Functions

    /// Executes list-notes query pipeline.
    ///
    /// Pipeline summary:
    /// 1) metadata fetch (fast path when possible)
    /// 2) title normalization fallback
    /// 3) selection (search/order/pagination)
    /// 4) optional body attachment/formatting
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      try Task.checkCancellation()
      let query = try Query(arguments: params.arguments)

      let metadataScript: String
      if let fastPath = query.metadataFastPathRequest {
        metadataScript = Self.metadataScriptForFirstNotes(
          limit: fastPath.limit,
          offset: fastPath.offset,
          account: fastPath.account
        )
      } else {
        metadataScript = Self.metadataScript(folderSelection: query.folderSelection)
      }
      let metadataExecutor = appleScriptFactory(metadataScript)

      let metadataNotes: [Models.Note]
      do {
        metadataNotes = try await MainActor.run {
          let descriptor = try metadataExecutor.run()
          return descriptor.parseNotes()
        }
      } catch {
        if let folderError = FolderScriptErrorMapper.map(error) {
          throw folderError
        }
        throw error
      }
      try Task.checkCancellation()

      let normalizedMetadataNotes = try await Self.resolveMissingMetadataTitles(
        in: metadataNotes,
        bodyBatchSize: bodyBatchSize,
        bodyLookup: bodyLookup
      )

      let dateFilteredNotes = Self.filterByDateRange(normalizedMetadataNotes, query: query)
      try Task.checkCancellation()

      let selection = try await Self.selectNotes(
        from: dateFilteredNotes,
        query: query,
        applyPagination: query.metadataFastPathRequest == nil,
        bodyBatchSize: bodyBatchSize,
        bodyLookup: bodyLookup
      )

      let selectedNotes = try await Self.attachBodiesIfNeeded(
        to: selection,
        query: query,
        bodyLookup: bodyLookup
      )

      try Task.checkCancellation()
      let payload = try selectedNotes.mcpPayload()
      return .init(content: [.text(payload)], isError: false)
    }

    /// Resolves empty metadata titles using body heading fallback for alignment
    /// with `get_note` and `batch_get_notes` title behavior.
    private static func resolveMissingMetadataTitles(
      in notes: [Models.Note],
      bodyBatchSize: Int,
      bodyLookup: @Sendable ([String]) async throws -> [String: String]
    ) async throws -> [Models.Note] {
      let emptyTitleIDs = notes
        .filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map(\.id)

      guard !emptyTitleIDs.isEmpty else {
        return notes
      }

      var bodyHTMLByID: [String: String] = [:]
      var start = 0
      while start < emptyTitleIDs.count {
        try Task.checkCancellation()
        let end = min(start + bodyBatchSize, emptyTitleIDs.count)
        let idsChunk = Array(emptyTitleIDs[start..<end])
        let chunkBodies = try await bodyLookup(idsChunk)
        bodyHTMLByID.merge(chunkBodies) { _, new in new }
        start = end
      }

      return notes.map { note in
        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else {
          return note
        }

        let resolvedTitle = BodyFormatter.resolvedTitle(
          metadataTitle: note.title,
          bodyHTML: bodyHTMLByID[note.id]
        )
        guard !resolvedTitle.isEmpty else {
          return note
        }

        return Models.Note(
          id: note.id,
          title: resolvedTitle,
          body: note.body,
          folder: note.folder,
          createdAt: note.createdAt,
          modifiedAt: note.modifiedAt
        )
      }
    }

    /// Applies deterministic traversal/search/pagination semantics to metadata notes.
    private static func selectNotes(
      from notes: [Models.Note],
      query: Query,
      applyPagination: Bool,
      bodyBatchSize: Int,
      bodyLookup: @Sendable ([String]) async throws -> [String: String]
    ) async throws -> SelectionResult {
      try Task.checkCancellation()
      let traversalNotes = makeTraversalOrder(from: notes, query: query)
      // For direction-only oldest, traversal reverses native order for matching. We
      // reverse back before return so the emitted slice remains in native order.
      let shouldRestoreNativeOrder = query.orderBy == nil && query.orderDirection == .oldest

      guard let searchText = query.searchText,
            let searchScope = query.searchScope else {
        let paged = applyPagination
          ? paginate(traversalNotes, offset: query.offset, limit: query.limit)
          : traversalNotes
        let notes = shouldRestoreNativeOrder ? Array(paged.reversed()) : paged
        return SelectionResult(notes: notes, cachedBodyHTML: [:])
      }

      var matchedCount = 0
      var selected: [Models.Note] = []
      var cachedBodyHTMLByID: [String: String] = [:]

      // Tracks offset/limit semantics after match evaluation.
      func consumeMatch(_ note: Models.Note) -> Bool {
        matchedCount += 1
        if matchedCount <= query.offset {
          return false
        }

        selected.append(note)
        if let limit = query.limit,
           selected.count >= limit {
          return true
        }

        return false
      }

      switch searchScope {
      case .title:
        for note in traversalNotes {
          try Task.checkCancellation()
          if matches(note.title, term: searchText),
             consumeMatch(note) {
            break
          }
        }

      case .body, .all:
        var pendingBodyChecks: [Models.Note] = []

        // Evaluates one body batch and returns `true` when selection is complete.
        func evaluatePendingBodyBatch() async throws -> Bool {
          guard !pendingBodyChecks.isEmpty else {
            return false
          }

          try Task.checkCancellation()
          let noteIDs = pendingBodyChecks.map { $0.id }
          let bodyHTMLByID = try await bodyLookup(noteIDs)
          try Task.checkCancellation()
          cachedBodyHTMLByID.merge(bodyHTMLByID) { _, new in new }

          for note in pendingBodyChecks {
            try Task.checkCancellation()
            let bodyHTML = bodyHTMLByID[note.id] ?? ""
            let bodyText = BodyFormatter.formatStoredBodyForOutput(
              bodyHTML: bodyHTML,
              title: note.title,
              as: .plain
            )
            if matches(bodyText, term: searchText),
               consumeMatch(note) {
              pendingBodyChecks.removeAll()
              return true
            }
          }

          pendingBodyChecks.removeAll()
          return false
        }

        for note in traversalNotes {
          try Task.checkCancellation()
          // Optimization for `all`: title match wins without body fetch.
          if searchScope == .all,
             matches(note.title, term: searchText) {
            if consumeMatch(note) {
              break
            }
            continue
          }

          pendingBodyChecks.append(note)
          if pendingBodyChecks.count >= bodyBatchSize,
             try await evaluatePendingBodyBatch() {
            break
          }
        }

        if query.limit.map({ selected.count < $0 }) ?? true {
          _ = try await evaluatePendingBodyBatch()
        }
      }

      let notes = shouldRestoreNativeOrder ? Array(selected.reversed()) : selected
      return SelectionResult(notes: notes, cachedBodyHTML: cachedBodyHTMLByID)
    }

    /// Attaches note bodies when explicitly requested.
    ///
    /// This reuses any bodies fetched during body search, then fetches only the
    /// remaining selected IDs. If a per-note body lookup fails, that note remains
    /// in results with `body = nil`.
    private static func attachBodiesIfNeeded(
      to selection: SelectionResult,
      query: Query,
      bodyLookup: @Sendable ([String]) async throws -> [String: String]
    ) async throws -> [Models.Note] {
      try Task.checkCancellation()
      guard query.includeBody else {
        return selection.notes
      }
      guard !selection.notes.isEmpty else {
        return []
      }

      var bodyHTMLByID = selection.cachedBodyHTML
      let missingIDs = selection.notes.compactMap { note in
        bodyHTMLByID[note.id] == nil ? note.id : nil
      }

      if !missingIDs.isEmpty {
        try Task.checkCancellation()
        let fetchedBodyHTML = try await bodyLookup(missingIDs)
        try Task.checkCancellation()
        bodyHTMLByID.merge(fetchedBodyHTML) { current, _ in current }
      }

      var notesWithBodies: [Models.Note] = []
      notesWithBodies.reserveCapacity(selection.notes.count)

      for note in selection.notes {
        try Task.checkCancellation()
        let formattedBody = bodyHTMLByID[note.id].map { bodyHTML in
          BodyFormatter.formatStoredBodyForOutput(
            bodyHTML: bodyHTML,
            title: note.title,
            as: query.bodyFormat
          )
        }
        notesWithBodies.append(Models.Note(
          id: note.id,
          title: note.title,
          body: formattedBody,
          folder: note.folder,
          createdAt: note.createdAt,
          modifiedAt: note.modifiedAt
        ))
      }

      return notesWithBodies
    }

    /// Filters notes by date-range constraints on `createdAt` and `modifiedAt`.
    ///
    /// Notes with empty timestamp strings are excluded when the corresponding
    /// date filter is present. All comparisons are inclusive (`>=` / `<=`).
    private static func filterByDateRange(
      _ notes: [Models.Note],
      query: Query
    ) -> [Models.Note] {
      guard query.createdAfter != nil || query.createdBefore != nil ||
            query.modifiedAfter != nil || query.modifiedBefore != nil else {
        return notes
      }
      return notes.filter { note in
        if let after = query.createdAfter {
          guard !note.createdAt.isEmpty, note.createdAt >= after else { return false }
        }
        if let before = query.createdBefore {
          guard !note.createdAt.isEmpty, note.createdAt <= before else { return false }
        }
        if let after = query.modifiedAfter {
          guard !note.modifiedAt.isEmpty, note.modifiedAt >= after else { return false }
        }
        if let before = query.modifiedBefore {
          guard !note.modifiedAt.isEmpty, note.modifiedAt <= before else { return false }
        }
        return true
      }
    }

    /// Produces the traversal order used before matching.
    ///
    /// - With `orderBy`, notes are globally sorted first.
    /// - Without `orderBy`, native Notes order is used.
    /// - `orderDirection=oldest` without `orderBy` traverses reversed native order.
    private static func makeTraversalOrder(from notes: [Models.Note], query: Query) -> [Models.Note] {
      var result = notes

      if let field = query.orderBy {
        let direction = query.orderDirection ?? .recent
        result.sort { lhs, rhs in
          let lhsKey = key(for: lhs, by: field)
          let rhsKey = key(for: rhs, by: field)
          if direction == .recent {
            return lhsKey > rhsKey
          }
          return lhsKey < rhsKey
        }
        return result
      }

      if query.orderDirection == .oldest {
        return Array(result.reversed())
      }

      return result
    }

    /// Applies offset/limit on already-selected note sequence.
    private static func paginate(_ notes: [Models.Note], offset: Int, limit: Int?) -> [Models.Note] {
      let afterOffset = Array(notes.dropFirst(offset))
      guard let limit else {
        return afterOffset
      }
      return Array(afterOffset.prefix(limit))
    }

    /// Resolves sortable timestamp key for configured order field.
    private static func key(for note: Models.Note, by field: Query.OrderField) -> String {
      switch field {
      case .created:
        return note.createdAt
      case .modified:
        return note.modifiedAt
      }
    }

    /// Text matcher used by title/body search.
    private static func matches(_ text: String, term: String) -> Bool {
      let normalizedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let normalizedTerm = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      return normalizedText.contains(normalizedTerm)
    }

    /// Performs a single batched AppleScript request to resolve bodies for IDs.
    private static func fetchBodies(for noteIDs: [String]) async throws -> [String: String] {
      guard !noteIDs.isEmpty else {
        return [:]
      }

      let script = bodyLookupScript(noteIDs: noteIDs)
      return try await MainActor.run {
        let descriptor = try AppleScript(source: script).run()
        return descriptor.parseNoteBodies()
      }
    }

    /// Builds metadata script scoped to all notes or a requested account/folder selection.
    private static func metadataScript(folderSelection: FolderSelection?) -> String {
      switch (folderSelection?.account, folderSelection?.folderPath) {
      case (nil, nil):
        return metadataScriptForAllNotes()

      case let (.some(account), nil):
        return metadataScriptForAccount(account: account)

      case let (.some(account), .some(folderPath)):
        return metadataScriptForSpecificPath(
          account: account,
          folderPath: folderPath
        )

      case let (nil, .some(folderPath)):
        return metadataScriptForPathAcrossAccounts(folderPath: folderPath)
      }
    }

    /// Generates unscoped metadata script for all notes.
    private static func metadataScriptForAllNotes() -> String {
      """
      tell application "Notes"
          set output to {}
          repeat with n in every note
              set theId to id of n as string
              set theName to name of n as string
              set theCreated to creation date of n
              set theModified to modification date of n
              set theFolderName to ""
              try
                  set theFolderName to name of (container of n) as string
              end try
              set end of output to {theId, theName, theCreated, theModified, theFolderName}
          end repeat
          return output
      end tell
      """
    }

    /// Fast path for simple metadata-only list queries.
    ///
    /// This supports optional account scoping and offset pagination while keeping
    /// descriptor output identical to the default metadata scripts:
    /// `{id, title, createdAt, modifiedAt, folder}`.
    private static func metadataScriptForFirstNotes(limit: Int, offset: Int, account: String?) -> String {
      let startIndex = offset + 1
      let escapedAccount = account?.escapedForAppleScriptLiteral() ?? ""

      return """
      tell application "Notes"
          set startIndex to \(startIndex)
          set maxCount to \(limit)
          set accountName to "\(escapedAccount)"
          set output to {}

          if accountName is "" then
              set totalCount to count of notes
              set endIndex to startIndex + maxCount - 1
              if startIndex > totalCount then
                  return output
              end if
              if endIndex > totalCount then
                  set endIndex to totalCount
              end if

              repeat with i from startIndex to endIndex
                  set n to note i
                  set theId to id of n as string
                  set theName to name of n as string
                  set theCreated to creation date of n
                  set theModified to modification date of n
                  set theFolderName to ""
                  try
                      set theFolderName to name of (container of n) as string
                  end try
                  set end of output to {theId, theName, theCreated, theModified, theFolderName}
              end repeat
          else
              try
                  set targetAccount to first account whose name is accountName
              on error
                  error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
              end try

              set totalCount to count of notes of targetAccount
              set endIndex to startIndex + maxCount - 1
              if startIndex > totalCount then
                  return output
              end if
              if endIndex > totalCount then
                  set endIndex to totalCount
              end if

              repeat with i from startIndex to endIndex
                  set n to note i of targetAccount
                  set theId to id of n as string
                  set theName to name of n as string
                  set theCreated to creation date of n
                  set theModified to modification date of n
                  set theFolderName to ""
                  try
                      set theFolderName to name of (container of n) as string
                  end try
                  set end of output to {theId, theName, theCreated, theModified, theFolderName}
              end repeat
          end if

          return output
      end tell
      """
    }

    /// Generates account-scoped metadata script.
    private static func metadataScriptForAccount(account: String) -> String {
      let escapedAccount = account.escapedForAppleScriptLiteral()

      return """
      tell application "Notes"
          set accountName to "\(escapedAccount)"

          try
              set targetAccount to first account whose name is accountName
          on error
              error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
          end try

          set output to {}
          tell targetAccount
              repeat with n in every note
                  set theId to id of n as string
                  set theName to name of n as string
                  set theCreated to creation date of n
                  set theModified to modification date of n
                  set theFolderName to ""
                  try
                      set theFolderName to name of (container of n) as string
                  end try
                  set end of output to {theId, theName, theCreated, theModified, theFolderName}
              end repeat
          end tell
          return output
      end tell
      """
    }

    /// Generates metadata script for one account-scoped folder path.
    ///
    /// Path traversal is segment-based to support nested folders safely.
    private static func metadataScriptForSpecificPath(account: String, folderPath: FolderPath) -> String {
      let escapedAccount = account.escapedForAppleScriptLiteral()
      let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
      let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
      let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set accountName to "\(escapedAccount)"
          set fullPath to "\(escapedFullPath)"
          set folderLeaf to "\(escapedLeaf)"
          set pathSegments to {\(pathSegmentsLiteral)}

          try
              set targetAccount to first account whose name is accountName
          on error
              error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
          end try

          set currentFolder to missing value
          repeat with segmentName in pathSegments
              set segmentValue to segmentName as string
              if currentFolder is missing value then
                  try
                      set currentFolder to first folder of targetAccount whose name is segmentValue
                  on error
                      error "\(FolderScriptErrorPrefix.folderNotFound)" & segmentValue & "::" & fullPath
                  end try
              else
                  try
                      set currentFolder to first folder of currentFolder whose name is segmentValue
                  on error
                      error "\(FolderScriptErrorPrefix.folderNotFound)" & segmentValue & "::" & fullPath
                  end try
              end if
          end repeat

          set output to {}
          tell currentFolder
              repeat with n in every note
                  set theId to id of n as string
                  set theName to name of n as string
                  set theCreated to creation date of n
                  set theModified to modification date of n
                  set end of output to {theId, theName, theCreated, theModified, folderLeaf}
              end repeat
          end tell
          return output
      end tell
      """
    }

    /// Generates metadata script for cross-account folder resolution.
    ///
    /// The script resolves the path across accounts and fails explicitly on
    /// ambiguity to preserve deterministic tool behavior.
    private static func metadataScriptForPathAcrossAccounts(folderPath: FolderPath) -> String {
      let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
      let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
      let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set fullPath to "\(escapedFullPath)"
          set folderLeaf to "\(escapedLeaf)"
          set pathSegments to {\(pathSegmentsLiteral)}
          set matchingFolders to {}
          set accountNames to {}

          repeat with acc in every account
              try
                  set currentFolder to missing value
                  repeat with segmentName in pathSegments
                      set segmentValue to segmentName as string
                      if currentFolder is missing value then
                          set currentFolder to first folder of acc whose name is segmentValue
                      else
                          set currentFolder to first folder of currentFolder whose name is segmentValue
                      end if
                  end repeat

                  set end of matchingFolders to currentFolder
                  set end of accountNames to (name of acc as string)
              end try
          end repeat

          if (count of matchingFolders) is 0 then
              error "\(FolderScriptErrorPrefix.folderNotFound)" & folderLeaf & "::" & fullPath
          else if (count of matchingFolders) > 1 then
              set previousDelimiters to AppleScript's text item delimiters
              set AppleScript's text item delimiters to "\(FolderScriptErrorPrefix.accountSeparator)"
              set accountsPayload to accountNames as string
              set AppleScript's text item delimiters to previousDelimiters
              error "\(FolderScriptErrorPrefix.folderAmbiguous)" & fullPath & "::" & accountsPayload
          end if

          set targetFolder to item 1 of matchingFolders
          set output to {}
          tell targetFolder
              repeat with n in every note
                  set theId to id of n as string
                  set theName to name of n as string
                  set theCreated to creation date of n
                  set theModified to modification date of n
                  set end of output to {theId, theName, theCreated, theModified, folderLeaf}
              end repeat
          end tell
          return output
      end tell
      """
    }

    /// Builds a script that fetches `{id, body}` tuples for each requested ID.
    private static func bodyLookupScript(noteIDs: [String]) -> String {
      let identifiers = noteIDs
        .map { "\"\($0.escapedForAppleScriptLiteral())\"" }
        .joined(separator: ", ")

      return """
      tell application "Notes"
          set output to {}
          repeat with noteID in {\(identifiers)}
              try
                  set n to first note whose id is (noteID as string)
                  set end of output to {(id of n as string), (body of n as string)}
              end try
          end repeat
          return output
      end tell
      """
    }

    /// Internal selection container used between search and body-attach phases.
    private struct SelectionResult: Sendable {
      let notes: [Models.Note]
      let cachedBodyHTML: [String: String]
    }
  }
}
