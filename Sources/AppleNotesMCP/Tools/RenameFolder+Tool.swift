import Foundation
import MCP

extension Tool {
  /// `rename_folder` renames a folder path while preserving its location.
  struct RenameFolder: Blueprint {

    // MARK: Properties

    static let name: String = "rename_folder"

    static let description: String = "Rename an Apple Notes folder path. Supports nested paths and optional account scoping."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "account": .object([
          "type": "string",
          "description": "Optional account name scope for folder resolution."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Folder path to rename. Supports nesting with '/': 'Parent/Child'. Case-sensitive."
        ]),
        "newName": .object([
          "type": "string",
          "description": "New leaf folder name. Must not contain '/'."
        ])
      ]),
      "required": .array([.string("folder"), .string("newName")]),
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the AppleScript execution factory.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Executes folder rename while preserving parent location.
    ///
    /// Edge cases:
    /// - no-op rename (`newName == current leaf`) returns `renamed=false`.
    /// - top-level system folders cannot be renamed.
    /// - sibling name conflicts are surfaced as explicit errors.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let folderSelection = try Self.parseFolderSelection(arguments: params.arguments)
      let newName = try Self.parseNewName(arguments: params.arguments)

      let script = Self.renameScript(folderSelection: folderSelection, newName: newName)
      let executor = appleScriptFactory(script)

      do {
        let renamed = try await MainActor.run {
          let descriptor = try executor.run()
          guard let parsed = Self.parseRenameResult(from: descriptor) else {
            throw Error.RenameFolder.invalidScriptResponse
          }
          return parsed
        }

        let payload = try renamed.mcpPayload()
        return .init(content: [.text(payload)], isError: false)
      } catch let error as Error.RenameFolder {
        throw error
      } catch let error as Error.FolderResolution {
        throw error
      } catch {
        if let folderError = FolderScriptErrorMapper.map(error) {
          throw folderError
        }
        if let systemFolder = FolderMutationScriptErrorPayload.cannotModifySystemFolder(from: error) {
          throw Error.RenameFolder.cannotModifySystemFolder(systemFolder)
        }
        if let conflictingName = FolderMutationScriptErrorPayload.folderNameConflict(from: error) {
          throw Error.RenameFolder.folderNameConflict(conflictingName)
        }
        throw error
      }
    }

    // MARK: Parsing

    /// Parses source folder selection and enforces required folder path.
    private static func parseFolderSelection(arguments: [String: MCP.Value]?) throws -> FolderSelection {
      let selection = try FolderResolution.parseOptionalFolderSelection(from: arguments)
      guard let selection, selection.folderPath != nil else {
        throw Error.RenameFolder.missingFolder
      }
      return selection
    }

    /// Parses and validates the new leaf folder name.
    ///
    /// `newName` intentionally forbids `/` so callers cannot change depth in a
    /// rename operation.
    private static func parseNewName(arguments: [String: MCP.Value]?) throws(Error.RenameFolder) -> String {
      guard let rawNewName = arguments?["newName"] else {
        throw .missingNewName
      }
      guard let value = rawNewName.stringValue else {
        throw .invalidNewNameType
      }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw .emptyNewName
      }
      guard !trimmed.contains("/") else {
        throw .invalidNewNameContainsPathSeparator
      }
      return trimmed
    }

    // MARK: Script

    /// Routes script generation by scope mode.
    private static func renameScript(folderSelection: FolderSelection, newName: String) -> String {
      switch (folderSelection.account, folderSelection.folderPath) {
      case let (.some(account), .some(folderPath)):
        return scopedRenameScript(account: account, folderPath: folderPath, newName: newName)
      case let (nil, .some(folderPath)):
        return crossAccountRenameScript(folderPath: folderPath, newName: newName)
      case (.some, nil), (nil, nil):
        preconditionFailure("Folder path is required for rename_folder script generation.")
      }
    }

    /// Generates account-scoped rename script.
    ///
    /// Script behavior:
    /// - resolves source folder by segments,
    /// - blocks system-folder mutations,
    /// - handles no-op rename and sibling conflicts,
    /// - returns both old and new paths.
    private static func scopedRenameScript(account: String, folderPath: FolderPath, newName: String) -> String {
      let escapedAccount = account.escapedForAppleScriptLiteral()
      let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
      let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
      let escapedParentPath = parentPath(for: folderPath).escapedForAppleScriptLiteral()
      let escapedNewName = newName.escapedForAppleScriptLiteral()
      let depth = folderPath.segments.count - 1
      let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set accountName to "\(escapedAccount)"
          set fullPath to "\(escapedFullPath)"
          set folderLeaf to "\(escapedLeaf)"
          set parentPath to "\(escapedParentPath)"
          set newName to "\(escapedNewName)"
          set depthValue to \(depth)
          set pathSegments to {\(pathSegmentsLiteral)}

          try
              set targetAccount to first account whose name is accountName
          on error
              error "\(FolderScriptErrorPrefix.accountNotFound)" & accountName
          end try

          set targetFolder to missing value
          repeat with segmentName in pathSegments
              set segmentValue to segmentName as string
              if targetFolder is missing value then
                  try
                      set targetFolder to first folder of targetAccount whose name is segmentValue
                  on error
                      error "\(FolderScriptErrorPrefix.folderNotFound)" & segmentValue & "::" & fullPath
                  end try
              else
                  try
                      set targetFolder to first folder of targetFolder whose name is segmentValue
                  on error
                      error "\(FolderScriptErrorPrefix.folderNotFound)" & segmentValue & "::" & fullPath
                  end try
              end if
          end repeat

          set parentContainer to container of targetFolder
          if (class of parentContainer is account) and ((folderLeaf is "Notes") or (folderLeaf is "Recently Deleted")) then
              error "\(FolderMutationScriptErrorPrefix.cannotModifySystemFolder)" & folderLeaf
          end if

          if folderLeaf is newName then
              set renamedFlag to 0
              set resolvedName to folderLeaf
              set newPath to fullPath
          else
              set hasConflict to false
              try
                  set existingSibling to first folder of parentContainer whose name is newName
                  if (id of existingSibling as string) is not (id of targetFolder as string) then
                      set hasConflict to true
                  end if
              on error
                  set hasConflict to false
              end try

              if hasConflict then
                  error "\(FolderMutationScriptErrorPrefix.folderNameConflict)" & newName
              end if

              set name of targetFolder to newName
              set renamedFlag to 1
              set resolvedName to name of targetFolder as string

              if parentPath is "" then
                  set newPath to resolvedName
              else
                  set newPath to parentPath & "/" & resolvedName
              end if
          end if

          return {accountName, fullPath, newPath, resolvedName, parentPath, depthValue, renamedFlag}
      end tell
      """
    }

    /// Generates cross-account rename script with path ambiguity detection.
    private static func crossAccountRenameScript(folderPath: FolderPath, newName: String) -> String {
      let escapedFullPath = folderPath.fullPath.escapedForAppleScriptLiteral()
      let escapedLeaf = folderPath.leafName.escapedForAppleScriptLiteral()
      let escapedParentPath = parentPath(for: folderPath).escapedForAppleScriptLiteral()
      let escapedNewName = newName.escapedForAppleScriptLiteral()
      let depth = folderPath.segments.count - 1
      let pathSegmentsLiteral = folderPath.segments.appleScriptStringListLiteral()

      return """
      tell application "Notes"
          set fullPath to "\(escapedFullPath)"
          set folderLeaf to "\(escapedLeaf)"
          set parentPath to "\(escapedParentPath)"
          set newName to "\(escapedNewName)"
          set depthValue to \(depth)
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
          set accountName to item 1 of accountNames
          set parentContainer to container of targetFolder

          if (class of parentContainer is account) and ((folderLeaf is "Notes") or (folderLeaf is "Recently Deleted")) then
              error "\(FolderMutationScriptErrorPrefix.cannotModifySystemFolder)" & folderLeaf
          end if

          if folderLeaf is newName then
              set renamedFlag to 0
              set resolvedName to folderLeaf
              set newPath to fullPath
          else
              set hasConflict to false
              try
                  set existingSibling to first folder of parentContainer whose name is newName
                  if (id of existingSibling as string) is not (id of targetFolder as string) then
                      set hasConflict to true
                  end if
              on error
                  set hasConflict to false
              end try

              if hasConflict then
                  error "\(FolderMutationScriptErrorPrefix.folderNameConflict)" & newName
              end if

              set name of targetFolder to newName
              set renamedFlag to 1
              set resolvedName to name of targetFolder as string

              if parentPath is "" then
                  set newPath to resolvedName
              else
                  set newPath to parentPath & "/" & resolvedName
              end if
          end if

          return {accountName, fullPath, newPath, resolvedName, parentPath, depthValue, renamedFlag}
      end tell
      """
    }

    // MARK: Response Parsing

    /// Parses `{account, oldPath, newPath, name, parentPath, depth, renamed}`
    /// rename result tuple.
    private static func parseRenameResult(from descriptor: NSAppleEventDescriptor) -> Models.RenameFolderResult? {
      guard descriptor.numberOfItems == 7 else {
        return nil
      }

      let account = descriptor.atIndex(1)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let oldPath = descriptor.atIndex(2)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let newPath = descriptor.atIndex(3)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let name = descriptor.atIndex(4)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let parentPath = descriptor.atIndex(5)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let depth = Int(descriptor.atIndex(6)?.int32Value ?? -1)
      let renamedFlag = Int(descriptor.atIndex(7)?.int32Value ?? -1)

      guard !account.isEmpty, !oldPath.isEmpty, !newPath.isEmpty, !name.isEmpty else {
        return nil
      }
      guard depth >= 0 else {
        return nil
      }
      guard renamedFlag == 0 || renamedFlag == 1 else {
        return nil
      }

      return Models.RenameFolderResult(
        account: account,
        oldPath: oldPath,
        newPath: newPath,
        name: name,
        parentPath: parentPath,
        depth: depth,
        renamed: renamedFlag == 1
      )
    }

    /// Computes parent path from normalized segments.
    private static func parentPath(for folderPath: FolderPath) -> String {
      guard folderPath.segments.count > 1 else {
        return ""
      }
      return folderPath.segments.dropLast().joined(separator: "/")
    }
  }
}
