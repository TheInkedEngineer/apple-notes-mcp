import Foundation

extension Error {
  /// Validation/parsing errors for `get_note` tool input/response handling.
  enum GetNote: LocalizedError, Equatable {
    case missingID
    case invalidIDType
    case emptyID
    case invalidBodyFormatType
    case invalidBodyFormatValue(String)
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
      case .invalidBodyFormatType:
        return "Invalid 'bodyFormat' value: expected a string ('plain', 'markdown', or 'html')."
      case .invalidBodyFormatValue(let value):
        return "Invalid 'bodyFormat' value '\(value)': expected 'plain', 'markdown', or 'html'."
      case let .noteNotFound(id):
        return "Could not find note '\(id)'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for get_note."
      }
    }
  }
}
