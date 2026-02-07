import Foundation

extension Error {
  /// Validation/runtime errors for `rename_folder`.
  enum RenameFolder: LocalizedError, Equatable {
    case missingFolder
    case missingNewName
    case invalidNewNameType
    case emptyNewName
    case invalidNewNameContainsPathSeparator
    case cannotModifySystemFolder(String)
    case folderNameConflict(String)
    case invalidScriptResponse

    var errorDescription: String? {
      switch self {
      case .missingFolder:
        return "Missing required parameter: 'folder'."
      case .missingNewName:
        return "Missing required parameter: 'newName'."
      case .invalidNewNameType:
        return "Invalid 'newName' value: expected a string."
      case .emptyNewName:
        return "Invalid 'newName' value: expected a non-empty string."
      case .invalidNewNameContainsPathSeparator:
        return "Invalid 'newName' value: folder names cannot contain '/'."
      case let .cannotModifySystemFolder(name):
        return "Cannot modify system folder '\(name)'."
      case let .folderNameConflict(name):
        return "A sibling folder named '\(name)' already exists."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for rename_folder."
      }
    }
  }
}
