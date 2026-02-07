import Foundation

extension Date {
  /// Canonical ISO8601 timestamp style used by MCP note payloads.
  /// Keep this centralized so all tools emit consistent date strings.
  ///
  /// `ISO8601FormatStyle` emits UTC (`Z`) timestamps. AppleScript date values are
  /// interpreted from local timezone input and normalized to UTC output here.
  static let notesTimestamp = ISO8601FormatStyle(includingFractionalSeconds: true)
    .dateSeparator(.dash)
    .timeSeparator(.colon)
}
