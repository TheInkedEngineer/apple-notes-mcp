import Foundation
import MCP

extension Tool {
  /// `create_note` creates a new Apple Note and returns its metadata/content.
  struct CreateNote: Blueprint {

    // MARK: Properties

    static let name: String = "create_note"

    static let description: String = "Create a new note in Apple Notes. Body accepts plain text by default, rich HTML with bodyFormat='html', or markdown with bodyFormat='markdown' (markdown is converted to rich HTML before saving). If you want literal markdown text, use bodyFormat='plain'. Optional account and nested folder path control placement. The tool stores the visible in-note title as rich heading content and then sets Notes metadata title (name) after creation to avoid duplicate title lines."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "title": .object([
          "type": "string",
          "description": "Note title (required, non-empty)."
        ]),
        "body": .object([
          "type": "string",
          "description": "Optional note body content."
        ]),
        "bodyFormat": .object([
          "type": "string",
          "enum": .array([.string("plain"), .string("html"), .string("markdown")]),
          "description": "Body input format. Use 'plain' (default) for text, 'html' for rich formatting, or 'markdown' to convert markdown into rich HTML before saving. If you want raw markdown stored verbatim, use 'plain'."
        ]),
        "account": .object([
          "type": "string",
          "description": "Optional account name (for example: iCloud, On My Mac). Case-sensitive."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Optional folder path. Supports nesting with '/': 'Parent/Child'. Case-sensitive."
        ])
      ]),
      "required": .array([.string("title")]),
      "additionalProperties": false
    ])

    /// Factory seam used by tests to inject deterministic AppleScript behavior.
    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the script execution factory.
    ///
    /// Tests capture generated scripts and return synthetic descriptors through
    /// this seam.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Creates a note with title/body/folder options.
    ///
    /// Edge cases:
    /// - markdown input is rendered to Notes-friendly HTML.
    /// - account/folder resolution errors reuse shared folder error contract.
    /// - returned body is normalized to plain text for stable client output.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let arguments = params.arguments
      let title = try Self.parseTitle(arguments: arguments)
      let body = try Self.parseBody(arguments: arguments)
      let bodyFormat = try Self.parseBodyFormat(arguments: arguments)
      let folderSelection = try Self.parseFolderSelection(arguments: arguments)

      let preparedBody = BodyFormatter.prepareForNotes(body, format: bodyFormat)
      let composedBody = BodyFormatter.composeStoredBodyHTML(title: title, preparedBody: preparedBody)
      let script = Self.createNoteScript(
        title: title,
        body: composedBody,
        folderSelection: folderSelection
      )

      let executor = appleScriptFactory(script)

      do {
        let note = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsedNote = descriptor.parseSingleNote() else {
            throw Error.CreateNote.invalidScriptResponse
          }
          return Self.formatBodyForOutput(parsedNote, fallbackTitle: title)
        }

        let payload = try [note].mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.FolderResolution {
        throw error
      } catch let error as Error.CreateNote {
        throw error
      } catch {
        if let mappedError = FolderScriptErrorMapper.map(error) {
          throw mappedError
        }
        throw error
      }
    }

    // MARK: Parsing

    /// Parses required note title.
    private static func parseTitle(arguments: [String: MCP.Value]?) throws(Error.CreateNote) -> String {
      guard let rawTitle = arguments?["title"] else {
        throw .missingTitle
      }
      guard let title = rawTitle.stringValue else {
        throw .invalidTitleType
      }

      let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedTitle.isEmpty else {
        throw .emptyTitle
      }

      return trimmedTitle
    }

    /// Parses optional note body.
    private static func parseBody(arguments: [String: MCP.Value]?) throws(Error.CreateNote) -> String {
      guard let rawBody = arguments?["body"] else {
        return ""
      }
      guard let body = rawBody.stringValue else {
        throw .invalidBodyType
      }
      return body
    }

    /// Parses input body format (`plain`, `html`, `markdown`).
    private static func parseBodyFormat(arguments: [String: MCP.Value]?) throws(Error.CreateNote) -> BodyInputFormat {
      guard let rawFormat = arguments?["bodyFormat"] else {
        return .plain
      }
      guard let formatValue = rawFormat.stringValue else {
        throw .invalidBodyFormatType
      }
      guard let bodyFormat = BodyInputFormat(rawValue: formatValue) else {
        throw .invalidBodyFormatValue(formatValue)
      }
      return bodyFormat
    }

    /// Parses optional account/folder placement arguments.
    private static func parseFolderSelection(arguments: [String: MCP.Value]?) throws(Error.FolderResolution) -> FolderSelection? {
      try FolderResolution.parseOptionalFolderSelection(from: arguments)
    }

    /// Normalizes returned note body/title for stable API output.
    ///
    /// When metadata title is empty, falls back to caller title used during
    /// creation so output remains deterministic.
    private static func formatBodyForOutput(_ note: Models.Note, fallbackTitle: String) -> Models.Note {
      let resolvedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : note.title
      guard let bodyHTML = note.body else {
        return Models.Note(
          id: note.id,
          title: resolvedTitle,
          body: note.body,
          folder: note.folder,
          createdAt: note.createdAt,
          modifiedAt: note.modifiedAt
        )
      }
      return Models.Note(
        id: note.id,
        title: resolvedTitle,
        body: BodyFormatter.formatStoredBodyForOutput(
          bodyHTML: bodyHTML,
          title: resolvedTitle,
          as: .plain
        ),
        folder: note.folder,
        createdAt: note.createdAt,
        modifiedAt: note.modifiedAt
      )
    }

    // MARK: Script

    /// All user-provided string values must be escaped before script interpolation.
    private static func createNoteScript(
      title: String,
      body: String,
      folderSelection: FolderSelection?
    ) -> String {
      let escapedTitle = title.escapedForAppleScriptLiteral()
      let escapedBody = body.escapedForAppleScriptLiteral()

      switch (folderSelection?.account, folderSelection?.folderPath) {
      case (nil, nil):
        return """
        tell application "Notes"
            set titleValue to "\(escapedTitle)"
            set bodyValue to "\(escapedBody)"
            set n to make new note with properties {name:"", body:bodyValue}
            set name of n to titleValue
            set theId to id of n as string
            set theName to name of n as string
            set theBody to body of n as string
            set theCreated to creation date of n
            set theModified to modification date of n
            set theFolderName to name of (container of n) as string
            return {theId, theName, theBody, theCreated, theModified, theFolderName}
        end tell
        """

      case let (.some(account), nil):
        let escapedAccount = account.escapedForAppleScriptLiteral()
        return """
        tell application "Notes"
            set titleValue to "\(escapedTitle)"
            set bodyValue to "\(escapedBody)"
            set accountName to "\(escapedAccount)"

            try
                set targetAccount to first account whose name is accountName
            on error
                error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
            end try

            tell targetAccount
                set n to make new note with properties {name:"", body:bodyValue}
                set name of n to titleValue
                set theId to id of n as string
                set theName to name of n as string
                set theBody to body of n as string
                set theCreated to creation date of n
                set theModified to modification date of n
                set theFolderName to name of (container of n) as string
            end tell

            return {theId, theName, theBody, theCreated, theModified, theFolderName}
        end tell
        """

      case let (.some(account), .some(folderPath)):
        let escapedAccount = account.escapedForAppleScriptLiteral()
        let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
        let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
        let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

        return """
        tell application "Notes"
            set titleValue to "\(escapedTitle)"
            set bodyValue to "\(escapedBody)"
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

            tell currentFolder
                set n to make new note with properties {name:"", body:bodyValue}
            end tell
            set name of n to titleValue

            set theId to id of n as string
            set theName to name of n as string
            set theBody to body of n as string
            set theCreated to creation date of n
            set theModified to modification date of n
            set theFolderName to folderLeaf
            return {theId, theName, theBody, theCreated, theModified, theFolderName}
        end tell
        """

      case let (nil, .some(folderPath)):
        let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
        let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
        let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

        return """
        tell application "Notes"
            set titleValue to "\(escapedTitle)"
            set bodyValue to "\(escapedBody)"
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
            tell targetFolder
                set n to make new note with properties {name:"", body:bodyValue}
            end tell
            set name of n to titleValue

            set theId to id of n as string
            set theName to name of n as string
            set theBody to body of n as string
            set theCreated to creation date of n
            set theModified to modification date of n
            set theFolderName to folderLeaf
            return {theId, theName, theBody, theCreated, theModified, theFolderName}
        end tell
        """
      }
    }
  }
}
