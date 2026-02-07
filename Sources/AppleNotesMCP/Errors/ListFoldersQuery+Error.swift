import Foundation

extension Error {
  /// Validation/parsing errors for `list_folders` query arguments.
  enum ListFoldersQuery: LocalizedError, Equatable {
    case invalidAccountType
    case emptyAccount

    var errorDescription: String? {
      switch self {
      case .invalidAccountType:
        return "Invalid 'account' value: expected a string."
      case .emptyAccount:
        return "Invalid 'account' value: expected a non-empty string."
      }
    }
  }
}
