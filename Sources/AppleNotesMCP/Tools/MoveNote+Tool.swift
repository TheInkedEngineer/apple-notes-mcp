import Foundation
import MCP

extension Tool {
  /// `move_note` moves an existing note to a destination folder.
  struct MoveNote: Blueprint {

    // MARK: Properties

    static let name: String = "move_note"

    static let description: String = "Move an Apple Note by ID to a destination folder path, optionally scoped to an account. Returns destination metadata; title is best-effort and can be empty when Notes metadata name is empty. Same-account moves preserve the note ID and timestamps. Cross-account moves recreate the note at the destination: the note gets a new ID, timestamps reset, and attachments may not transfer. Cross-account moves auto-create the destination folder if it does not exist."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "id": .object([
          "type": "string",
          "description": "The unique Apple Notes identifier."
        ]),
        "account": .object([
          "type": "string",
          "description": "Optional account name scope for destination folder resolution. When the note belongs to a different account, a cross-account move is performed (create + delete)."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Destination folder path. Supports nesting with '/': 'Parent/Child'. Case-sensitive."
        ])
      ]),
      "required": .array([.string("id"), .string("folder")]),
      "additionalProperties": false
    ])

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

    /// Moves a note to a destination folder path.
    ///
    /// Edge cases:
    /// - folder path is required.
    /// - destination resolution can be account-scoped or cross-account.
    /// - ambiguous folder paths are mapped through shared folder mapper.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let noteID = try Self.parseNoteID(arguments: params.arguments)
      let folderSelection = try Self.parseFolderSelection(arguments: params.arguments)
      let source = Self.script(noteID: noteID, folderSelection: folderSelection)
      let executor = appleScriptFactory(source)

      do {
        let moved = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsed = descriptor.parseMoveResult() else {
            throw Error.MoveNote.invalidScriptResponse
          }
          return parsed
        }

        let payload = try moved.mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.MoveNote {
        throw error
      } catch let error as Error.FolderResolution {
        throw error
      } catch {
        if let missingID = NoteScriptErrorMapper.noteNotFoundID(from: error) {
          throw Error.MoveNote.noteNotFound(missingID)
        }
        if let folderError = FolderScriptErrorMapper.map(error) {
          throw folderError
        }
        throw error
      }
    }

    // MARK: Parsing

    /// Parses required note ID with shared helper.
    private static func parseNoteID(arguments: [String: MCP.Value]?) throws(Error.MoveNote) -> String {
      try ToolArgumentParsing.parseRequiredNoteID(
        arguments: arguments,
        missing: Error.MoveNote.missingID,
        invalidType: Error.MoveNote.invalidIDType,
        empty: Error.MoveNote.emptyID
      )
    }

    /// Parses destination selection and enforces `folder` presence.
    private static func parseFolderSelection(arguments: [String: MCP.Value]?) throws -> FolderSelection {
      let selection = try FolderResolution.parseOptionalFolderSelection(from: arguments)
      guard let selection, selection.folderPath != nil else {
        throw Error.MoveNote.missingFolder
      }
      return selection
    }

    // MARK: Script

    /// Generates the AppleScript source for moving a note.
    ///
    /// Two destination modes are supported (scoped and unscoped), and within
    /// each mode the script detects same-account vs cross-account at runtime:
    ///
    /// - **Same-account**: uses `move n to targetFolder`, preserving the
    ///   original note ID and timestamps.
    /// - **Cross-account**: Apple Notes has no native cross-account move.
    ///   The script creates a new note at the destination with
    ///   `{body:originalBody}` (without `name`, because body HTML already
    ///   contains the title as its first heading — setting `name` too would
    ///   duplicate it), then deletes the original. New ID, reset timestamps,
    ///   attachments may not transfer.
    ///
    /// Cross-account folder auto-creation:
    /// - **Scoped** (`account` + `folder`): missing destination folder
    ///   segments are created on the fly in the target account.
    /// - **Unscoped** (`folder` only): the destination folder must already
    ///   exist; no auto-creation is performed.
    private static func script(noteID: String, folderSelection: FolderSelection) -> String {
      let escapedID = noteID.escapedForAppleScriptLiteral()

      switch (folderSelection.account, folderSelection.folderPath) {
      case let (.some(account), .some(folderPath)):
        let escapedAccount = account.escapedForAppleScriptLiteral()
        let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
        let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
        let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

        return """
        tell application "Notes"
            set noteID to "\(escapedID)"
            set accountName to "\(escapedAccount)"
            set fullPath to "\(escapedFullPath)"
            set folderLeaf to "\(escapedLeaf)"
            set pathSegments to {\(pathSegmentsLiteral)}

            try
                set n to first note whose id is noteID
            on error
                error "\(NoteScriptErrorPrefix.noteNotFound)" & noteID
            end try

            try
                set targetAccount to first account whose name is accountName
            on error
                error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
            end try

            -- Detect whether note belongs to destination account
            set isSameAccount to false
            try
                set testNote to first note of targetAccount whose id is noteID
                set isSameAccount to true
            end try

            set accountID to id of targetAccount as string
            set currentFolder to missing value
            repeat with segmentName in pathSegments
                set segmentValue to segmentName as string
                if currentFolder is missing value then
                    set rootMatch to missing value
                    repeat with f in (every folder of targetAccount whose name is segmentValue)
                        try
                            if (id of container of f as string) is accountID then
                                set rootMatch to f
                                exit repeat
                            end if
                        end try
                    end repeat
                    if rootMatch is missing value then
                        if isSameAccount then
                            error "\(FolderScriptErrorPrefix.folderNotFound)" & segmentValue & "::" & fullPath
                        else
                            set currentFolder to make new folder at targetAccount with properties {name:segmentValue}
                        end if
                    else
                        set currentFolder to rootMatch
                    end if
                else
                    try
                        set currentFolder to first folder of currentFolder whose name is segmentValue
                    on error
                        if isSameAccount then
                            error "\(FolderScriptErrorPrefix.folderNotFound)" & segmentValue & "::" & fullPath
                        else
                            set currentFolder to make new folder at currentFolder with properties {name:segmentValue}
                        end if
                    end try
                end if
            end repeat

            if isSameAccount then
                move n to currentFolder
                set theID to id of n as string
                set theTitle to name of n as string
                set theModified to modification date of n
            else
                set originalBody to body of n
                set newNote to make new note at currentFolder with properties {body:originalBody}
                delete n
                set theID to id of newNote as string
                set theTitle to name of newNote as string
                set theModified to modification date of newNote
            end if
            return {theID, theTitle, accountName, fullPath, folderLeaf, theModified}
        end tell
        """

      case let (nil, .some(folderPath)):
        let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
        let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
        let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

        return """
        tell application "Notes"
            set noteID to "\(escapedID)"
            set fullPath to "\(escapedFullPath)"
            set folderLeaf to "\(escapedLeaf)"
            set pathSegments to {\(pathSegmentsLiteral)}
            set matchingFolders to {}
            set accountNames to {}

            try
                set n to first note whose id is noteID
            on error
                error "\(NoteScriptErrorPrefix.noteNotFound)" & noteID
            end try

            repeat with acc in every account
                try
                    set accID to id of acc as string
                    set currentFolder to missing value
                    repeat with segmentName in pathSegments
                        set segmentValue to segmentName as string
                        if currentFolder is missing value then
                            set rootMatch to missing value
                            repeat with f in (every folder of acc whose name is segmentValue)
                                try
                                    if (id of container of f as string) is accID then
                                        set rootMatch to f
                                        exit repeat
                                    end if
                                end try
                            end repeat
                            if rootMatch is missing value then
                                error "no root match"
                            end if
                            set currentFolder to rootMatch
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
            set targetAccountName to item 1 of accountNames
            -- Detect whether note belongs to destination account
            set isSameAccount to false
            try
                set destAccount to first account whose name is targetAccountName
                set testNote to first note of destAccount whose id is noteID
                set isSameAccount to true
            end try

            if isSameAccount then
                move n to targetFolder
                set theID to id of n as string
                set theTitle to name of n as string
                set theModified to modification date of n
            else
                set originalBody to body of n
                set newNote to make new note at targetFolder with properties {body:originalBody}
                delete n
                set theID to id of newNote as string
                set theTitle to name of newNote as string
                set theModified to modification date of newNote
            end if
            return {theID, theTitle, targetAccountName, fullPath, folderLeaf, theModified}
        end tell
        """

      case (.some, nil), (nil, nil):
        preconditionFailure("Folder path is required for move_note script generation.")
      }
    }
  }
}
