import Foundation

extension Error {
  /// Validation/parsing errors for `list_notes` query arguments.
  enum ListNotesQuery: LocalizedError {
    case invalidLimitType
    case negativeLimit
    case invalidOffsetType
    case negativeOffset
    case offsetRequiresLimit
    case invalidSearchTextType
    case emptySearchText
    case invalidSearchInType
    case invalidSearchInValue(String)
    case searchInRequiresSearchText
    case invalidIncludeBodyType
    case invalidBodyFormatType
    case invalidBodyFormatValue(String)
    case invalidOrderByType
    case invalidOrderByValue(String)
    case invalidOrderDirectionType
    case invalidOrderDirectionValue(String)
    case invalidCreatedAfterType
    case invalidCreatedBeforeType
    case invalidModifiedAfterType
    case invalidModifiedBeforeType
    case invalidCreatedAfterValue(String)
    case invalidCreatedBeforeValue(String)
    case invalidModifiedAfterValue(String)
    case invalidModifiedBeforeValue(String)
    case contradictoryCreatedRange
    case contradictoryModifiedRange

    var errorDescription: String? {
      switch self {
      case .invalidLimitType:
        return "Invalid 'limit' value: expected an integer."
      case .negativeLimit:
        return "Invalid 'limit' value: expected a non-negative integer."
      case .invalidOffsetType:
        return "Invalid 'offset' value: expected an integer."
      case .negativeOffset:
        return "Invalid 'offset' value: expected a non-negative integer."
      case .offsetRequiresLimit:
        return "Invalid query: 'offset' requires a positive 'limit'."
      case .invalidSearchTextType:
        return "Invalid 'searchText' value: expected a string."
      case .emptySearchText:
        return "Invalid 'searchText' value: expected a non-empty string."
      case .invalidSearchInType:
        return "Invalid 'searchIn' value: expected a string ('title', 'body', or 'all')."
      case .invalidSearchInValue(let value):
        return "Invalid 'searchIn' value '\(value)': expected 'title', 'body', or 'all'."
      case .searchInRequiresSearchText:
        return "Invalid query: 'searchIn' requires 'searchText'."
      case .invalidIncludeBodyType:
        return "Invalid 'includeBody' value: expected a boolean."
      case .invalidBodyFormatType:
        return "Invalid 'bodyFormat' value: expected a string ('plain', 'markdown', or 'html')."
      case .invalidBodyFormatValue(let value):
        return "Invalid 'bodyFormat' value '\(value)': expected 'plain', 'markdown', or 'html'."
      case .invalidOrderByType:
        return "Invalid 'orderBy' value: expected a string ('modified' or 'created')."
      case .invalidOrderByValue(let value):
        return "Invalid 'orderBy' value '\(value)': expected 'modified' or 'created'."
      case .invalidOrderDirectionType:
        return "Invalid 'orderDirection' value: expected a string ('recent' or 'oldest')."
      case .invalidOrderDirectionValue(let value):
        return "Invalid 'orderDirection' value '\(value)': expected 'recent' or 'oldest'."
      case .invalidCreatedAfterType:
        return "Invalid 'createdAfter' value: expected an ISO8601 date string."
      case .invalidCreatedBeforeType:
        return "Invalid 'createdBefore' value: expected an ISO8601 date string."
      case .invalidModifiedAfterType:
        return "Invalid 'modifiedAfter' value: expected an ISO8601 date string."
      case .invalidModifiedBeforeType:
        return "Invalid 'modifiedBefore' value: expected an ISO8601 date string."
      case .invalidCreatedAfterValue(let value):
        return "Invalid 'createdAfter' value '\(value)': expected ISO8601 format (e.g. '2025-01-15', '2025-01-15T09:30:00Z', or '2025-01-15T09:30:00.000Z')."
      case .invalidCreatedBeforeValue(let value):
        return "Invalid 'createdBefore' value '\(value)': expected ISO8601 format (e.g. '2025-01-15', '2025-01-15T09:30:00Z', or '2025-01-15T09:30:00.000Z')."
      case .invalidModifiedAfterValue(let value):
        return "Invalid 'modifiedAfter' value '\(value)': expected ISO8601 format (e.g. '2025-01-15', '2025-01-15T09:30:00Z', or '2025-01-15T09:30:00.000Z')."
      case .invalidModifiedBeforeValue(let value):
        return "Invalid 'modifiedBefore' value '\(value)': expected ISO8601 format (e.g. '2025-01-15', '2025-01-15T09:30:00Z', or '2025-01-15T09:30:00.000Z')."
      case .contradictoryCreatedRange:
        return "Invalid query: 'createdAfter' must not be later than 'createdBefore'."
      case .contradictoryModifiedRange:
        return "Invalid query: 'modifiedAfter' must not be later than 'modifiedBefore'."
      }
    }
  }
}
