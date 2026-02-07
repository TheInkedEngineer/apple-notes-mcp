import Foundation

extension Error {
  /// Validation and script-response errors for `batch_delete_notes`.
  enum BatchDeleteNotes: LocalizedError, Equatable {
    case missingIDs
    case invalidIDsType
    case emptyIDs
    case invalidIDElementType(index: Int)
    case emptyID(index: Int)
    case invalidScriptResponse

    var errorDescription: String? {
      switch self {
      case .missingIDs:
        return "Missing required parameter: 'ids'."
      case .invalidIDsType:
        return "Invalid 'ids' value: expected an array of strings."
      case let .invalidIDElementType(index):
        return "Invalid 'ids' value at index \(index): expected a string."
      case .emptyIDs:
        return "Invalid 'ids' value: expected at least one note ID."
      case let .emptyID(index):
        return "Invalid 'ids' value at index \(index): expected a non-empty string."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for batch_delete_notes."
      }
    }
  }
}
