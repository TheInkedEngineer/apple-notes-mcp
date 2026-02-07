import Foundation

extension Error {
  /// Validation and script-mapping errors for `move_note`.
  enum MoveNote: LocalizedError, Equatable {
    case missingID
    case invalidIDType
    case emptyID
    case missingFolder
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
      case .missingFolder:
        return "Missing required parameter: 'folder'."
      case let .noteNotFound(id):
        return "Could not find note '\(id)'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for move_note."
      }
    }
  }
}
