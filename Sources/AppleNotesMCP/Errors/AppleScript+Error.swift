import Foundation

extension Error {
  /// Errors emitted while compiling/executing AppleScript.
  enum AppleScript: LocalizedError {
    case failedToCreate
    case custom(info: String)

    var errorDescription: String? {
      switch self {
      case .failedToCreate:
        "Failed to create AppleScript. Please report this as an issue."
      case let .custom(info):
        "Script failed during execution with error info: \(info)."
      }
    }
  }
}
