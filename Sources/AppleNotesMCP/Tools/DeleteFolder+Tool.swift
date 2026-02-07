import Foundation
import MCP

private enum DeleteFolderScriptErrorPrefix {
  static let cannotDeleteSystemFolder = "MCP_CANNOT_DELETE_SYSTEM_FOLDER::"
}

extension Tool {
  /// `delete_folder` deletes a folder path and all descendants.
  struct DeleteFolder: Blueprint {

    // MARK: Properties

    static let name: String = "delete_folder"

    static let description: String = """
    Delete an Apple Notes folder path. This is destructive: all subfolders are deleted, and notes inside are moved to Recently Deleted (without preserving folder hierarchy) and later permanently removed by Notes.
    """

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "account": .object([
          "type": "string",
          "description": "Optional account name scope for folder resolution."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Folder path to delete. Supports nesting with '/': 'Parent/Child'. Case-sensitive."
        ]),
        "confirmCascadeDelete": .object([
          "type": "boolean",
          "description": "Must be true. Safety gate acknowledging that deleting a folder also deletes all subfolders and removes folder context for contained notes."
        ])
      ]),
      "required": .array([.string("folder"), .string("confirmCascadeDelete")]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the AppleScript execution factory.
    ///
    /// Tests replace this to validate destructive-flow logic without Notes.app.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Executes cascading folder deletion.
    ///
    /// Edge cases:
    /// - hard safety gate requires `confirmCascadeDelete == true`.
    /// - system folders (`Notes`, `Recently Deleted`) are blocked explicitly.
    /// - shared folder resolution errors are mapped via shared prefix mapper.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      try Self.parseConfirmCascadeDelete(arguments: params.arguments)
      let selection = try Self.parseFolderSelection(arguments: params.arguments)
      let source = Self.script(folderSelection: selection)
      let executor = appleScriptFactory(source)

      do {
        let result = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsed = Self.parseDeleteFolderResult(from: descriptor) else {
            throw Error.DeleteFolder.invalidScriptResponse
          }
          return parsed
        }

        let payload = try result.mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.DeleteFolder {
        throw error
      } catch let error as Error.FolderResolution {
        throw error
      } catch {
        if let folderError = FolderScriptErrorMapper.map(error) {
          throw folderError
        }
        if let systemFolder = Self.systemFolderName(from: error) {
          throw Error.DeleteFolder.cannotDeleteSystemFolder(systemFolder)
        }
        throw error
      }
    }

    // MARK: Parsing

    /// Validates the explicit destructive-action acknowledgement.
    ///
    /// This intentionally rejects string values like `"true"` and accepts only
    /// a boolean literal `true`.
    private static func parseConfirmCascadeDelete(arguments: [String: MCP.Value]?) throws(Error.DeleteFolder) {
      guard let rawConfirm = arguments?["confirmCascadeDelete"] else {
        throw .missingConfirmCascadeDelete
      }
      guard case let .bool(confirm) = rawConfirm else {
        throw .invalidConfirmCascadeDeleteType
      }
      guard confirm else {
        throw .confirmCascadeDeleteMustBeTrue
      }
    }

    /// Parses folder selection and enforces folder presence.
    private static func parseFolderSelection(arguments: [String: MCP.Value]?) throws -> FolderSelection {
      let selection = try FolderResolution.parseOptionalFolderSelection(from: arguments)
      guard let selection, selection.folderPath != nil else {
        throw Error.DeleteFolder.missingFolder
      }
      return selection
    }

    // MARK: Script

    /// Routes script generation by scope mode.
    private static func script(folderSelection: FolderSelection) -> String {
      switch (folderSelection.account, folderSelection.folderPath) {
      case let (.some(account), .some(folderPath)):
        return scopedDeleteScript(account: account, folderPath: folderPath)
      case let (nil, .some(folderPath)):
        return crossAccountDeleteScript(folderPath: folderPath)
      case (.some, nil), (nil, nil):
        preconditionFailure("Folder path is required for delete_folder script generation.")
      }
    }

    /// Generates account-scoped deletion script.
    ///
    /// Path traversal is segment-based to support nested folders safely.
    private static func scopedDeleteScript(account: String, folderPath: FolderPath) -> String {
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

          set parentContainer to container of currentFolder
          if (class of parentContainer is account) and ((folderLeaf is "Notes") or (folderLeaf is "Recently Deleted")) then
              error "\(DeleteFolderScriptErrorPrefix.cannotDeleteSystemFolder)" & folderLeaf
          end if

          delete currentFolder
          return {accountName, fullPath, folderLeaf}
      end tell
      """
    }

    /// Generates cross-account deletion script with ambiguity detection.
    private static func crossAccountDeleteScript(folderPath: FolderPath) -> String {
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

          repeat with acc in accounts
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
          set targetAccountName to item 1 of accountNames

          set parentContainer to container of targetFolder
          if (class of parentContainer is account) and ((folderLeaf is "Notes") or (folderLeaf is "Recently Deleted")) then
              error "\(DeleteFolderScriptErrorPrefix.cannotDeleteSystemFolder)" & folderLeaf
          end if

          delete targetFolder
          return {targetAccountName, fullPath, folderLeaf}
      end tell
      """
    }

    /// Parses `{account, path, folder}` delete response tuple.
    private static func parseDeleteFolderResult(from descriptor: NSAppleEventDescriptor) -> Models.DeleteFolderResult? {
      guard descriptor.numberOfItems == 3 else {
        return nil
      }

      let account = descriptor.atIndex(1)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let path = descriptor.atIndex(2)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let folder = descriptor.atIndex(3)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

      guard !account.isEmpty, !path.isEmpty, !folder.isEmpty else {
        return nil
      }

      return Models.DeleteFolderResult(
        account: account,
        path: path,
        folder: folder,
        deleted: true
      )
    }

    /// Extracts system-folder protection payload from script errors.
    private static func systemFolderName(from error: any Swift.Error) -> String? {
      guard let scriptError = error as? Error.AppleScript else {
        return nil
      }
      guard case let .custom(info) = scriptError else {
        return nil
      }
      return ScriptErrorPayload.extract(after: DeleteFolderScriptErrorPrefix.cannotDeleteSystemFolder, in: info)
    }
  }
}
