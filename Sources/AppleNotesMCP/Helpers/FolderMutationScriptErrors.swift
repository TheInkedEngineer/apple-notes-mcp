import Foundation

/// Structured prefix contract for folder mutation script errors.
enum FolderMutationScriptErrorPrefix {
  static let cannotModifySystemFolder = "MCP_CANNOT_MODIFY_SYSTEM_FOLDER::"
  static let folderNameConflict = "MCP_FOLDER_NAME_CONFLICT::"
  static let invalidMoveTarget = "MCP_INVALID_MOVE_TARGET::"
}

enum FolderMutationScriptErrorPayload {
  static func cannotModifySystemFolder(from error: any Swift.Error) -> String? {
    extract(after: FolderMutationScriptErrorPrefix.cannotModifySystemFolder, from: error)
  }

  static func folderNameConflict(from error: any Swift.Error) -> String? {
    extract(after: FolderMutationScriptErrorPrefix.folderNameConflict, from: error)
  }

  static func invalidMoveTarget(from error: any Swift.Error) -> String? {
    extract(after: FolderMutationScriptErrorPrefix.invalidMoveTarget, from: error)
  }

  private static func extract(after prefix: String, from error: any Swift.Error) -> String? {
    guard let scriptError = error as? Error.AppleScript else {
      return nil
    }
    guard case let .custom(info) = scriptError else {
      return nil
    }
    return ScriptErrorPayload.extract(after: prefix, in: info)
  }
}
