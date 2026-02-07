import Foundation

extension Error {
  /// Validation/runtime errors for `move_folder`.
  enum MoveFolder: LocalizedError, Equatable {
    case missingFolder
    case missingDestinationFolder
    case invalidDestinationFolderType
    case emptyDestinationFolder
    case invalidDestinationFolderPathFormat(String)
    case invalidDestinationAccountType
    case emptyDestinationAccount
    case noOpMove
    case invalidMoveTarget(String)
    case cannotModifySystemFolder(String)
    case sourceFolderNotFound(String)
    case sourceFolderAmbiguous(String, [String])
    case subToolFailed(tool: String, reason: String)

    var errorDescription: String? {
      switch self {
      case .missingFolder:
        return "Missing required parameter: 'folder'."
      case .missingDestinationFolder:
        return "Missing required parameter: 'destinationFolder'."
      case .invalidDestinationFolderType:
        return "Invalid 'destinationFolder' value: expected a string."
      case .emptyDestinationFolder:
        return "Invalid 'destinationFolder' value: expected a non-empty string."
      case let .invalidDestinationFolderPathFormat(path):
        return "Invalid destination folder path format '\(path)'. Use 'FolderName' or nested paths like 'Parent/Child'."
      case .invalidDestinationAccountType:
        return "Invalid 'destinationAccount' value: expected a string."
      case .emptyDestinationAccount:
        return "Invalid 'destinationAccount' value: expected a non-empty string."
      case .noOpMove:
        return "The source folder is already under the requested destination parent."
      case let .invalidMoveTarget(details):
        return "Invalid move target: \(details)"
      case let .cannotModifySystemFolder(name):
        return "Cannot modify system folder '\(name)'."
      case let .sourceFolderNotFound(path):
        return "Source folder not found: '\(path)'."
      case let .sourceFolderAmbiguous(path, accounts):
        let accountList = accounts.joined(separator: ", ")
        return "Source folder '\(path)' exists in multiple accounts (\(accountList)). Specify 'account' to disambiguate."
      case let .subToolFailed(tool, reason):
        return "Sub-tool '\(tool)' failed: \(reason)"
      }
    }
  }
}
