import Foundation

extension String {
  /// Escapes a string for safe embedding inside AppleScript string literals.
  func escapedForAppleScriptLiteral() -> String {
    let normalizedNewlines = self
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    return normalizedNewlines
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\t", with: "\\t")
      .replacingOccurrences(of: "\n", with: "\\n")
  }
}

extension Array where Element == String {
  /// Builds an AppleScript list literal from string values.
  ///
  /// Example output: `"A", "B", "C"`
  func appleScriptStringListLiteral() -> String {
    self
      .map { "\"\($0.escapedForAppleScriptLiteral())\"" }
      .joined(separator: ", ")
  }
}
