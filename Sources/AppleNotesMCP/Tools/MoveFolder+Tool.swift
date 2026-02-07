import Foundation
import MCP

extension Tool {
  /// `move_folder` moves one folder to a destination parent folder.
  ///
  /// Implemented as orchestration: creates destination tree, moves notes by ID,
  /// then deletes source. Note IDs are preserved; folder object identity is not.
  struct MoveFolder: Blueprint {

    // MARK: Properties

    static let name: String = "move_folder"

    static let description: String = "Move an Apple Notes folder path into a destination parent folder. Supports optional account scoping for source and destination. Use 'Notes' as destinationFolder to place the folder at the top level. Non-iCloud accounts (e.g. Google) only support top-level folders."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "account": .object([
          "type": "string",
          "description": "Optional source account scope for source folder resolution."
        ]),
        "folder": .object([
          "type": "string",
          "description": "Source folder path to move. Supports nesting with '/': 'Parent/Child'. Case-sensitive."
        ]),
        "destinationAccount": .object([
          "type": "string",
          "description": "Optional destination account scope. Defaults to resolved source account. Non-iCloud accounts (e.g. Google) only support top-level folders."
        ]),
        "destinationFolder": .object([
          "type": "string",
          "description": "Destination parent folder path where the source folder will be placed as a child. Do not include the source folder name — it is appended automatically. Example: to move 'Path/To/Example' into 'NewPath', use 'NewPath' (not 'NewPath/Example'). Supports nesting with '/': 'Parent/Child'. Case-sensitive. Use 'Notes' to move the folder to the top level. Non-iCloud accounts (e.g. Google) only support top-level folders — use 'Notes' as the destination for those accounts."
        ])
      ]),
      "required": .array([.string("folder"), .string("destinationFolder")]),
      "additionalProperties": false
    ])

    private let operations: Operations

    /// Injects the operations dependency.
    ///
    /// Tests pass custom `Operations` with mock closures. Production uses
    /// `Operations.makeDefault(appleScriptFactory:)` to wire real tool instances.
    init(
      operations: Operations? = nil,
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.operations = operations ?? Operations.makeDefault(appleScriptFactory: appleScriptFactory)
    }

    // MARK: Functions

    /// Executes folder move via sub-tool orchestration:
    /// 1) Parse input
    /// 2) Discover source via list_folders
    /// 3) Validate preconditions
    /// 4) Create destination folder tree
    /// 5) Move notes folder-by-folder
    /// 6) Delete source (only if zero failures)
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      try Task.checkCancellation()

      // Phase 0 — Parse input
      let sourceSelection = try Self.parseSourceSelection(arguments: params.arguments)
      let destinationPath = try Self.parseDestinationFolderPath(arguments: params.arguments)
      let destinationAccountOverride = try Self.parseDestinationAccount(arguments: params.arguments)

      // Phase 1 — Discover source via list_folders
      let allFolders: [Models.Folder]
      do {
        allFolders = try await operations.listFolders(sourceSelection.account)
      } catch {
        throw Error.MoveFolder.subToolFailed(tool: "list_folders", reason: error.localizedDescription)
      }

      let sourcePath = sourceSelection.folderPath.fullPath
      let matchingFolders: [(folder: Models.Folder, account: String)]

      if let account = sourceSelection.account {
        matchingFolders = allFolders
          .filter { $0.account == account && $0.path == sourcePath }
          .map { ($0, $0.account) }
      } else {
        let grouped = Dictionary(grouping: allFolders.filter { $0.path == sourcePath }, by: \.account)
        matchingFolders = grouped.values.compactMap { folders in
          folders.first.map { ($0, $0.account) }
        }
      }

      guard !matchingFolders.isEmpty else {
        throw Error.MoveFolder.sourceFolderNotFound(sourcePath)
      }
      guard matchingFolders.count == 1 else {
        let accounts = matchingFolders.map(\.account).sorted()
        throw Error.MoveFolder.sourceFolderAmbiguous(sourcePath, accounts)
      }

      let sourceFolder = matchingFolders[0].folder
      let sourceAccount = sourceFolder.account
      let destinationAccount = destinationAccountOverride ?? sourceAccount

      // Collect subtree: source folder + all descendants
      let subtree = allFolders
        .filter { $0.account == sourceAccount && ($0.path == sourcePath || $0.path.hasPrefix(sourcePath + "/")) }
        .sorted { $0.depth < $1.depth }

      let sourceLeaf = sourceSelection.folderPath.leafName

      // Phase 2 — Validate preconditions
      let isDestinationRoot = destinationPath.fullPath == "Notes"
      let destinationRootPath = isDestinationRoot
        ? sourceLeaf
        : destinationPath.fullPath + "/" + sourceLeaf

      if sourceAccount == destinationAccount {
        let effectiveDestination = isDestinationRoot ? "" : destinationPath.fullPath
        if sourceFolder.parentPath == effectiveDestination {
          throw Error.MoveFolder.noOpMove
        }
        if destinationRootPath == sourcePath || destinationRootPath.hasPrefix(sourcePath + "/") {
          throw Error.MoveFolder.invalidMoveTarget("Destination cannot be the source folder or any of its descendants.")
        }
      }

      // System folder protection: top-level Notes or Recently Deleted
      if sourceFolder.depth == 0 && (sourceFolder.name == "Notes" || sourceFolder.name == "Recently Deleted") {
        throw Error.MoveFolder.cannotModifySystemFolder(sourceFolder.name)
      }

      try Task.checkCancellation()

      // Phase 3 — Create destination folder tree (top-down)
      var createdFolders: [String] = []
      for folder in subtree {
        let destPath = Self.destinationPath(for: folder.path, sourceRoot: sourcePath, destinationRoot: destinationRootPath)
        let createResult: Models.CreateFolderResult
        do {
          createResult = try await operations.createFolder(destinationAccount, destPath)
        } catch {
          let reason = destPath.contains("/")
            ? error.localizedDescription + " This account may not support nested folders."
            : error.localizedDescription
          throw Error.MoveFolder.subToolFailed(tool: "create_folder(\(destPath))", reason: reason)
        }
        if !createResult.alreadyExisted {
          createdFolders.append(destPath)
        }
      }

      try Task.checkCancellation()

      // Phase 4 — Move notes folder-by-folder
      var movedNoteCount = 0
      var failedNoteMoves: [Models.MoveFolderNoteFailure] = []

      for folder in subtree {
        try Task.checkCancellation()

        let notes: [Models.Note]
        do {
          notes = try await operations.listNotes(sourceAccount, folder.path)
        } catch {
          throw Error.MoveFolder.subToolFailed(tool: "list_notes(\(folder.path))", reason: error.localizedDescription)
        }
        let destPath = Self.destinationPath(for: folder.path, sourceRoot: sourcePath, destinationRoot: destinationRootPath)

        for note in notes {
          do {
            _ = try await operations.moveNote(note.id, destinationAccount, destPath)
            movedNoteCount += 1
          } catch {
            failedNoteMoves.append(Models.MoveFolderNoteFailure(
              noteID: note.id,
              noteTitle: note.title,
              sourceFolder: folder.path,
              destinationFolder: destPath,
              reason: error.localizedDescription
            ))
          }
        }
      }

      // Phase 5 — Delete source (only if zero failures)
      var sourceDeleted = false
      if failedNoteMoves.isEmpty {
        do {
          _ = try await operations.deleteFolder(sourceAccount, sourcePath)
          sourceDeleted = true
        } catch {
          sourceDeleted = false
        }
      }

      // Phase 6 — Build and return result
      let moved = failedNoteMoves.isEmpty && sourceDeleted
      let partial = !failedNoteMoves.isEmpty && movedNoteCount > 0

      let result = Models.MoveFolderResult(
        sourceAccount: sourceAccount,
        sourcePath: sourcePath,
        destinationAccount: destinationAccount,
        destinationPath: destinationRootPath,
        folder: sourceLeaf,
        moved: moved,
        movedNoteCount: movedNoteCount,
        failedNoteMoves: failedNoteMoves,
        createdFolders: createdFolders,
        sourceDeleted: sourceDeleted,
        partial: partial
      )

      let payload = try result.mcpPayload()
      return .init(content: [.text(payload)], isError: false)
    }

    // MARK: Parsing

    /// Parses source folder selection and enforces source path presence.
    static func parseSourceSelection(arguments: [String: MCP.Value]?) throws -> SourceFolderSelection {
      let selection = try FolderResolution.parseOptionalFolderSelection(from: arguments)
      guard let selection, let sourcePath = selection.folderPath else {
        throw Error.MoveFolder.missingFolder
      }
      return SourceFolderSelection(account: selection.account, folderPath: sourcePath)
    }

    /// Parses destination parent folder path.
    ///
    /// Destination uses a dedicated parameter (`destinationFolder`) so source
    /// and destination validation errors are distinguishable in responses.
    static func parseDestinationFolderPath(arguments: [String: MCP.Value]?) throws -> FolderPath {
      guard let rawDestination = arguments?["destinationFolder"] else {
        throw Error.MoveFolder.missingDestinationFolder
      }
      guard let destinationValue = rawDestination.stringValue else {
        throw Error.MoveFolder.invalidDestinationFolderType
      }

      let trimmedPath = destinationValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedPath.isEmpty else {
        throw Error.MoveFolder.emptyDestinationFolder
      }

      do {
        return try FolderResolution.parseFolderPathString(trimmedPath)
      } catch let error {
        if case let .invalidFolderPathFormat(path) = error {
          throw Error.MoveFolder.invalidDestinationFolderPathFormat(path)
        }
        throw error
      }
    }

    /// Parses optional destination account override.
    static func parseDestinationAccount(arguments: [String: MCP.Value]?) throws(Error.MoveFolder) -> String? {
      guard let rawDestinationAccount = arguments?["destinationAccount"] else {
        return nil
      }
      guard let accountValue = rawDestinationAccount.stringValue else {
        throw .invalidDestinationAccountType
      }
      let trimmedAccount = accountValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedAccount.isEmpty else {
        throw .emptyDestinationAccount
      }
      return trimmedAccount
    }

    // MARK: Path Mapping

    /// Computes destination path for a source folder within the subtree.
    ///
    /// - Parameters:
    ///   - sourcePath: The specific folder path being mapped.
    ///   - sourceRoot: The root of the source subtree being moved.
    ///   - destinationRoot: The root of the destination subtree.
    /// - Returns: The corresponding destination path.
    static func destinationPath(for sourcePath: String, sourceRoot: String, destinationRoot: String) -> String {
      if sourcePath == sourceRoot {
        return destinationRoot
      }
      return destinationRoot + "/" + sourcePath.dropFirst(sourceRoot.count + 1)
    }
  }
}

struct SourceFolderSelection: Sendable {
  let account: String?
  let folderPath: FolderPath
}
