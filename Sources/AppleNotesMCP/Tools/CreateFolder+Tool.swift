import Foundation
import MCP

extension Tool {
  /// `create_folder` creates a folder path, creating missing segments in order.
  struct CreateFolder: Blueprint {

    // MARK: Properties

    static let name: String = "create_folder"

    static let description: String = "Create an Apple Notes folder path. Missing intermediate folders are created automatically (`mkdir -p` semantics). If `account` is omitted, the first folder segment must already exist in exactly one account to keep creation deterministic."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "account": .object([
          "type": "string",
          "description": "Optional account name scope for creation (for example: iCloud, On My Mac). Case-sensitive."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Folder path to create. Supports nesting with '/': 'Parent/Child'. Case-sensitive."
        ])
      ]),
      "required": .array([.string("folder")]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the AppleScript execution factory.
    ///
    /// Test suites provide deterministic executors through this seam so folder
    /// creation logic can be validated without touching Notes.app.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Executes folder creation with deterministic account resolution.
    ///
    /// Edge cases:
    /// - `folder` is required.
    /// - cross-account creation without `account` requires first segment to
    ///   exist in exactly one account.
    /// - folder resolution errors are surfaced as `Error.FolderResolution`.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let selection = try Self.parseFolderSelection(arguments: params.arguments)
      let source = Self.script(folderSelection: selection)
      let executor = appleScriptFactory(source)

      do {
        let result = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsed = Self.parseCreateFolderResult(from: descriptor) else {
            throw Error.CreateFolder.invalidScriptResponse
          }
          return parsed
        }

        let payload = try result.mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.CreateFolder {
        throw error
      } catch let error as Error.FolderResolution {
        throw error
      } catch {
        if let folderError = FolderScriptErrorMapper.map(error) {
          throw folderError
        }
        throw error
      }
    }

    // MARK: Parsing

    /// Parses and validates source folder selection.
    ///
    /// `create_folder` requires a concrete folder path even though shared
    /// parsing allows account-only selections for other tools.
    private static func parseFolderSelection(arguments: [String: MCP.Value]?) throws -> FolderSelection {
      let selection = try FolderResolution.parseOptionalFolderSelection(from: arguments)
      guard let selection, selection.folderPath != nil else {
        throw Error.CreateFolder.missingFolder
      }
      return selection
    }

    // MARK: Script

    /// Routes script generation by account-scoped vs cross-account behavior.
    private static func script(folderSelection: FolderSelection) -> String {
      switch (folderSelection.account, folderSelection.folderPath) {
      case let (.some(account), .some(folderPath)):
        return scopedCreateScript(account: account, folderPath: folderPath)
      case let (nil, .some(folderPath)):
        return crossAccountCreateScript(folderPath: folderPath)
      case (.some, nil), (nil, nil):
        preconditionFailure("Folder path is required for create_folder script generation.")
      }
    }

    /// Generates account-scoped `mkdir -p` AppleScript.
    ///
    /// `alreadyExistedFlag` starts at `1` and flips to `0` on the first
    /// created segment so response semantics remain deterministic.
    private static func scopedCreateScript(account: String, folderPath: FolderPath) -> String {
      let escapedAccount = account.escapedForAppleScriptLiteral()
      let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
      let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set accountName to "\(escapedAccount)"
          set fullPath to "\(escapedFullPath)"
          set pathSegments to {\(pathSegmentsLiteral)}
          set alreadyExistedFlag to 1

          try
              set targetAccount to first account whose name is accountName
          on error
              error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
          end try

          set accountID to id of targetAccount as string
          set firstSegment to item 1 of pathSegments as string
          set currentFolder to missing value
          repeat with f in (every folder of targetAccount whose name is firstSegment)
              try
                  if (id of container of f as string) is accountID then
                      set currentFolder to f
                      exit repeat
                  end if
              end try
          end repeat
          if currentFolder is missing value then
              set currentFolder to make new folder at targetAccount with properties {name:firstSegment}
              set alreadyExistedFlag to 0
          end if

          if (count of pathSegments) > 1 then
              repeat with segmentIndex from 2 to (count of pathSegments)
                  set segmentValue to item segmentIndex of pathSegments as string
                  try
                      set nextFolder to first folder of currentFolder whose name is segmentValue
                  on error
                      set nextFolder to make new folder at currentFolder with properties {name:segmentValue}
                      set alreadyExistedFlag to 0
                  end try
                  set currentFolder to nextFolder
              end repeat
          end if

          set leafName to name of currentFolder as string
          set depthValue to (count of pathSegments) - 1
          if depthValue > 0 then
              set previousDelimiters to AppleScript's text item delimiters
              set AppleScript's text item delimiters to "/"
              set parentSegments to items 1 thru -2 of pathSegments
              set parentPath to parentSegments as string
              set AppleScript's text item delimiters to previousDelimiters
          else
              set parentPath to ""
          end if

          return {accountName, fullPath, leafName, parentPath, depthValue, alreadyExistedFlag}
      end tell
      """
    }

    /// Generates cross-account script with first-segment disambiguation.
    ///
    /// Edge cases:
    /// - zero first-segment matches -> account must be specified.
    /// - multiple first-segment matches -> ambiguity error.
    /// - exactly one match -> create remaining segments under that account.
    private static func crossAccountCreateScript(folderPath: FolderPath) -> String {
      let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
      let escapedFirstSegment = folderPath.segments[0].escapedForAppleScriptLiteral()
      let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set fullPath to "\(escapedFullPath)"
          set firstSegment to "\(escapedFirstSegment)"
          set pathSegments to {\(pathSegmentsLiteral)}
          set matchingRoots to {}
          set matchingAccounts to {}

          repeat with acc in accounts
              set accID to id of acc as string
              repeat with f in (every folder of acc whose name is firstSegment)
                  try
                      if (id of container of f as string) is accID then
                          set end of matchingRoots to f
                          set end of matchingAccounts to (name of acc as string)
                          exit repeat
                      end if
                  end try
              end repeat
          end repeat

          if (count of matchingRoots) is 0 then
              error "\(FolderScriptErrorPrefix.accountRequiredForCreation)" & fullPath
          else if (count of matchingRoots) > 1 then
              set previousDelimiters to AppleScript's text item delimiters
              set AppleScript's text item delimiters to "\(FolderScriptErrorPrefix.accountSeparator)"
              set accountsPayload to matchingAccounts as string
              set AppleScript's text item delimiters to previousDelimiters
              error "\(FolderScriptErrorPrefix.folderAmbiguous)" & firstSegment & "::" & accountsPayload
          end if

          set currentFolder to item 1 of matchingRoots
          set accountName to item 1 of matchingAccounts
          set alreadyExistedFlag to 1

          if (count of pathSegments) > 1 then
              repeat with segmentIndex from 2 to (count of pathSegments)
                  set segmentValue to item segmentIndex of pathSegments as string
                  try
                      set nextFolder to first folder of currentFolder whose name is segmentValue
                  on error
                      set nextFolder to make new folder at currentFolder with properties {name:segmentValue}
                      set alreadyExistedFlag to 0
                  end try
                  set currentFolder to nextFolder
              end repeat
          end if

          set leafName to name of currentFolder as string
          set depthValue to (count of pathSegments) - 1
          if depthValue > 0 then
              set previousDelimiters to AppleScript's text item delimiters
              set AppleScript's text item delimiters to "/"
              set parentSegments to items 1 thru -2 of pathSegments
              set parentPath to parentSegments as string
              set AppleScript's text item delimiters to previousDelimiters
          else
              set parentPath to ""
          end if

          return {accountName, fullPath, leafName, parentPath, depthValue, alreadyExistedFlag}
      end tell
      """
    }

    // MARK: Response Parsing

    /// Parses the `{account, path, name, parentPath, depth, alreadyExisted}`
    /// tuple returned by create-folder scripts.
    private static func parseCreateFolderResult(from descriptor: NSAppleEventDescriptor) -> Models.CreateFolderResult? {
      guard descriptor.numberOfItems == 6 else {
        return nil
      }

      let account = descriptor.atIndex(1)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let path = descriptor.atIndex(2)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let name = descriptor.atIndex(3)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let parentPath = descriptor.atIndex(4)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let depth = Int(descriptor.atIndex(5)?.int32Value ?? -1)
      let alreadyExistedFlag = Int(descriptor.atIndex(6)?.int32Value ?? -1)

      guard !account.isEmpty, !path.isEmpty, !name.isEmpty else {
        return nil
      }
      guard depth >= 0 else {
        return nil
      }
      guard alreadyExistedFlag == 0 || alreadyExistedFlag == 1 else {
        return nil
      }

      return Models.CreateFolderResult(
        account: account,
        path: path,
        name: name,
        parentPath: parentPath,
        depth: depth,
        alreadyExisted: alreadyExistedFlag == 1
      )
    }
  }
}
