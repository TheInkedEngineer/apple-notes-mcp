import Foundation

extension Error {
  /// Validation and runtime errors for `create_note`.
  enum CreateNote: LocalizedError, Equatable {
    case missingTitle
    case invalidTitleType
    case emptyTitle
    case invalidBodyType
    case invalidBodyFormatType
    case invalidBodyFormatValue(String)
    case invalidScriptResponse

    var errorDescription: String? {
      switch self {
      case .missingTitle:
        return "Missing required parameter: 'title'."
      case .invalidTitleType:
        return "Invalid 'title' value: expected a string."
      case .emptyTitle:
        return "Invalid 'title' value: expected a non-empty string."
      case .invalidBodyType:
        return "Invalid 'body' value: expected a string."
      case .invalidBodyFormatType:
        return "Invalid 'bodyFormat' value: expected a string ('plain', 'html', or 'markdown')."
      case .invalidBodyFormatValue(let value):
        return "Invalid 'bodyFormat' value '\(value)': expected 'plain', 'html', or 'markdown'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for create_note."
      }
    }
  }
}
