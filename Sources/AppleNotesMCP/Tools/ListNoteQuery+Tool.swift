import Foundation
import MCP

extension Tool.ListNotes {
  /// Immutable query model for `list_notes`.
  struct Query: Sendable {
    let limit: Int?
    let offset: Int
    let searchText: String?
    let searchScope: SearchScope?
    let folderSelection: FolderSelection?
    let includeBody: Bool
    let bodyFormat: BodyOutputFormat
    let orderBy: OrderField?
    let orderDirection: OrderDirection?
    let createdAfter: String?
    let createdBefore: String?
    let modifiedAfter: String?
    let modifiedBefore: String?
    
    /// Parses and validates incoming `list_notes` arguments.
    ///
    /// Edge cases:
    /// - `limit=0` is treated as unlimited (`nil`).
    /// - `offset` requires a positive `limit`.
    /// - `searchIn` requires `searchText`.
    /// - `bodyFormat` is parsed even when `includeBody=false` (ignored later).
    init(arguments: [String: MCP.Value]?) throws {
      let parsedLimit: Int?
      if let rawLimit = arguments?["limit"] {
        guard let limit = rawLimit.intValue else {
          throw Error.ListNotesQuery.invalidLimitType
        }
        if limit < 0 {
          throw Error.ListNotesQuery.negativeLimit
        }
        parsedLimit = limit == 0 ? nil : limit
      } else {
        parsedLimit = nil
      }
      
      let parsedOffset: Int
      if let rawOffset = arguments?["offset"] {
        guard let offset = rawOffset.intValue else {
          throw Error.ListNotesQuery.invalidOffsetType
        }
        if offset < 0 {
          throw Error.ListNotesQuery.negativeOffset
        }
        parsedOffset = offset
      } else {
        parsedOffset = 0
      }
      
      if parsedOffset > 0,
         parsedLimit == nil {
        throw Error.ListNotesQuery.offsetRequiresLimit
      }
      
      let parsedSearchText: String?
      if let rawSearch = arguments?["searchText"] {
        guard let searchText = rawSearch.stringValue else {
          throw Error.ListNotesQuery.invalidSearchTextType
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          throw Error.ListNotesQuery.emptySearchText
        }
        parsedSearchText = trimmed
      } else {
        parsedSearchText = nil
      }
      
      let parsedSearchScope: SearchScope?
      if let rawSearchScope = arguments?["searchIn"] {
        guard let scopeValue = rawSearchScope.stringValue else {
          throw Error.ListNotesQuery.invalidSearchInType
        }
        guard let scope = SearchScope(rawValue: scopeValue) else {
          throw Error.ListNotesQuery.invalidSearchInValue(scopeValue)
        }
        parsedSearchScope = scope
      } else {
        parsedSearchScope = nil
      }
      
      if parsedSearchText == nil,
         parsedSearchScope != nil {
        throw Error.ListNotesQuery.searchInRequiresSearchText
      }

      let parsedFolderSelection = try FolderResolution.parseOptionalFolderSelection(from: arguments)

      if let rawIncludeBody = arguments?["includeBody"] {
        guard case let .bool(includeBody) = rawIncludeBody else {
          throw Error.ListNotesQuery.invalidIncludeBodyType
        }
        self.includeBody = includeBody
      } else {
        self.includeBody = false
      }

      if let rawBodyFormat = arguments?["bodyFormat"] {
        guard let bodyFormatValue = rawBodyFormat.stringValue else {
          throw Error.ListNotesQuery.invalidBodyFormatType
        }
        guard let bodyFormat = BodyOutputFormat(rawValue: bodyFormatValue) else {
          throw Error.ListNotesQuery.invalidBodyFormatValue(bodyFormatValue)
        }
        self.bodyFormat = bodyFormat
      } else {
        self.bodyFormat = .plain
      }
      
      if let rawOrderBy = arguments?["orderBy"] {
        guard let textValue = rawOrderBy.stringValue else {
          throw Error.ListNotesQuery.invalidOrderByType
        }
        guard let field = OrderField(rawValue: textValue) else {
          throw Error.ListNotesQuery.invalidOrderByValue(textValue)
        }
        self.orderBy = field
      } else {
        self.orderBy = nil
      }
      
      if let rawDirection = arguments?["orderDirection"] {
        guard let textValue = rawDirection.stringValue else {
          throw Error.ListNotesQuery.invalidOrderDirectionType
        }
        guard let direction = OrderDirection(rawValue: textValue) else {
          throw Error.ListNotesQuery.invalidOrderDirectionValue(textValue)
        }
        self.orderDirection = direction
      } else {
        self.orderDirection = nil
      }
      
      let parsedCreatedAfter = try Self.parseDateFilter(
        from: arguments, key: "createdAfter",
        typeError: .invalidCreatedAfterType,
        valueError: { .invalidCreatedAfterValue($0) },
        isBefore: false
      )

      let parsedCreatedBefore = try Self.parseDateFilter(
        from: arguments, key: "createdBefore",
        typeError: .invalidCreatedBeforeType,
        valueError: { .invalidCreatedBeforeValue($0) },
        isBefore: true
      )

      let parsedModifiedAfter = try Self.parseDateFilter(
        from: arguments, key: "modifiedAfter",
        typeError: .invalidModifiedAfterType,
        valueError: { .invalidModifiedAfterValue($0) },
        isBefore: false
      )

      let parsedModifiedBefore = try Self.parseDateFilter(
        from: arguments, key: "modifiedBefore",
        typeError: .invalidModifiedBeforeType,
        valueError: { .invalidModifiedBeforeValue($0) },
        isBefore: true
      )

      if let after = parsedCreatedAfter, let before = parsedCreatedBefore, after > before {
        throw Error.ListNotesQuery.contradictoryCreatedRange
      }
      if let after = parsedModifiedAfter, let before = parsedModifiedBefore, after > before {
        throw Error.ListNotesQuery.contradictoryModifiedRange
      }

      self.createdAfter = parsedCreatedAfter
      self.createdBefore = parsedCreatedBefore
      self.modifiedAfter = parsedModifiedAfter
      self.modifiedBefore = parsedModifiedBefore
      self.limit = parsedLimit
      self.offset = parsedOffset
      self.searchText = parsedSearchText
      self.folderSelection = parsedFolderSelection
      if parsedSearchText != nil {
        self.searchScope = parsedSearchScope ?? .title
      } else {
        self.searchScope = nil
      }
    }

    /// Returns a request for metadata fast-path retrieval when semantics allow.
    ///
    /// This path keeps traversal semantics unchanged while reducing AppleScript
    /// work for simple metadata-only queries.
    var metadataFastPathRequest: MetadataFastPathRequest? {
      guard let limit else {
        return nil
      }
      guard searchText == nil,
            searchScope == nil,
            includeBody == false,
            orderBy == nil,
            orderDirection == nil,
            createdAfter == nil,
            createdBefore == nil,
            modifiedAfter == nil,
            modifiedBefore == nil else {
        return nil
      }

      switch folderSelection {
      case nil:
        return MetadataFastPathRequest(limit: limit, offset: offset, account: nil)
      case let .some(selection):
        guard selection.folderPath == nil else {
          return nil
        }
        return MetadataFastPathRequest(limit: limit, offset: offset, account: selection.account)
      }
    }

    /// Inputs required to fetch a metadata window directly in AppleScript.
    struct MetadataFastPathRequest: Sendable, Equatable {
      let limit: Int
      let offset: Int
      let account: String?
    }
    
    /// User-facing search scopes for text filtering.
    enum SearchScope: String, Sendable {
      case title
      case body
      case all
    }
    
    /// Supported timestamp fields for ordering.
    enum OrderField: String, Sendable {
      case modified
      case created
    }
    
    /// Order direction semantics.
    enum OrderDirection: String, Sendable {
      case recent
      case oldest
    }

    // MARK: Date Filter Helpers

    /// Parses and validates a single date filter argument.
    ///
    /// - `isBefore`: when `true` and input is date-only, normalizes to end-of-day (23:59:59.999).
    ///   When `false` and input is date-only, normalizes to start-of-day (00:00:00.000).
    /// - Returns the canonical `Date.notesTimestamp` string, or `nil` when the argument is absent.
    private static func parseDateFilter(
      from arguments: [String: MCP.Value]?,
      key: String,
      typeError: Error.ListNotesQuery,
      valueError: (String) -> Error.ListNotesQuery,
      isBefore: Bool
    ) throws -> String? {
      guard let rawValue = arguments?[key] else {
        return nil
      }
      guard let stringValue = rawValue.stringValue else {
        throw typeError
      }
      guard !stringValue.isEmpty else {
        throw valueError("")
      }

      let dateOnly = isDateOnly(stringValue)

      guard var date = parseISO8601(stringValue) else {
        throw valueError(stringValue)
      }

      if dateOnly, isBefore {
        // Normalize date-only *Before to end-of-day: 23:59:59.999
        date = date.addingTimeInterval(86399.999)
      }

      return date.formatted(Date.notesTimestamp)
    }

    /// Detects whether a value is date-only (no time component).
    private static func isDateOnly(_ value: String) -> Bool {
      !value.contains("T")
    }

    /// Parses flexible ISO8601 input: full with fractional seconds, without fractional seconds,
    /// with timezone offset, or date-only.
    private static func parseISO8601(_ value: String) -> Date? {
      if isDateOnly(value) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
      }

      // Try with fractional seconds first.
      let withFractional = ISO8601DateFormatter()
      withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = withFractional.date(from: value) {
        return date
      }

      // Try without fractional seconds.
      let withoutFractional = ISO8601DateFormatter()
      withoutFractional.formatOptions = [.withInternetDateTime]
      if let date = withoutFractional.date(from: value) {
        return date
      }

      return nil
    }
  }
}
