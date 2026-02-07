import Foundation

extension Error {
  /// Shared folder path/lookup errors used across folder-aware tools.
  enum FolderResolution: LocalizedError, Equatable {
    case invalidAccountType
    case emptyAccount
    case invalidFolderType
    case emptyFolder
    case invalidFolderPathFormat(String)
    case folderNotFound(segment: String, path: String)
    case ambiguousFolder(path: String, accounts: [String])
    case accountNotFound(String)
    case accountRequiredForCreation(path: String)

    var errorDescription: String? {
      switch self {
      case .invalidAccountType:
        return "Invalid 'account' value: expected a string."
      case .emptyAccount:
        return "Invalid 'account' value: expected a non-empty string."
      case .invalidFolderType:
        return "Invalid 'folder' value: expected a string."
      case .emptyFolder:
        return "Invalid 'folder' value: expected a non-empty string."
      case let .invalidFolderPathFormat(path):
        return "Invalid folder path format '\(path)'. Use 'FolderName' or nested paths like 'Parent/Child'."
      case let .folderNotFound(segment, path):
        return "Could not find folder '\(segment)' in path '\(path)'."
      case let .ambiguousFolder(path, accounts):
        let accountsText = accounts.joined(separator: ", ")
        return "Folder path '\(path)' exists in multiple accounts: \(accountsText). Specify 'account' to disambiguate."
      case let .accountNotFound(account):
        return "Could not find account '\(account)'."
      case let .accountRequiredForCreation(path):
        return "Could not determine which account should contain '\(path)'. Specify 'account' to create this folder path."
      }
    }
  }
}
