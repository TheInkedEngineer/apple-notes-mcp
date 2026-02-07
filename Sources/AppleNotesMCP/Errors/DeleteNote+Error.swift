import Foundation

extension Error {
  /// Validation and script-mapping errors for `delete_note`.
  enum DeleteNote: LocalizedError, Equatable {
    case missingID
    case invalidIDType
    case emptyID
    case noteNotFound(String)
    case invalidScriptResponse

    var errorDescription: String? {
      switch self {
      case .missingID:
        return "Missing required parameter: 'id'."
      case .invalidIDType:
        return "Invalid 'id' value: expected a string."
      case .emptyID:
        return "Invalid 'id' value: expected a non-empty string."
      case let .noteNotFound(id):
        return "Could not find note '\(id)'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for delete_note."
      }
    }
  }
}
