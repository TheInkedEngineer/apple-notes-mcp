import Foundation

extension Error {
  /// Validation/runtime errors for `update_note`.
  enum UpdateNote: LocalizedError, Equatable {
    case missingID
    case invalidIDType
    case emptyID
    case noChangesRequested
    case invalidTitleType
    case emptyTitle
    case invalidBodyType
    case invalidBodyFormatType
    case invalidBodyFormatValue(String)
    case bodyModeRequiresBody
    case invalidBodyModeType
    case invalidBodyModeValue(String)
    case invalidOutputBodyFormatType
    case invalidOutputBodyFormatValue(String)
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
      case .noChangesRequested:
        return "Invalid request: provide at least one field to update ('title' or 'body')."
      case .invalidTitleType:
        return "Invalid 'title' value: expected a string."
      case .emptyTitle:
        return "Invalid 'title' value: expected a non-empty string."
      case .invalidBodyType:
        return "Invalid 'body' value: expected a string."
      case .invalidBodyFormatType:
        return "Invalid 'bodyFormat' value: expected a string ('plain', 'html', or 'markdown')."
      case let .invalidBodyFormatValue(value):
        return "Invalid 'bodyFormat' value '\(value)': expected 'plain', 'html', or 'markdown'."
      case .bodyModeRequiresBody:
        return "Invalid request: 'bodyMode' requires 'body'."
      case .invalidBodyModeType:
        return "Invalid 'bodyMode' value: expected a string ('replace', 'append', or 'prepend')."
      case let .invalidBodyModeValue(value):
        return "Invalid 'bodyMode' value '\(value)': expected 'replace', 'append', or 'prepend'."
      case .invalidOutputBodyFormatType:
        return "Invalid 'outputBodyFormat' value: expected a string ('plain', 'markdown', or 'html')."
      case let .invalidOutputBodyFormatValue(value):
        return "Invalid 'outputBodyFormat' value '\(value)': expected 'plain', 'markdown', or 'html'."
      case let .noteNotFound(id):
        return "Could not find note '\(id)'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for update_note."
      }
    }
  }
}
