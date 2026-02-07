import Foundation

/// Minimal stderr logger for CLI MCP runtime diagnostics.
enum Logger {
  static func info(_ message: String) {
    write("[INFO] \(message)")
  }

  static func error(_ message: String) {
    write("[ERROR] \(message)")
  }

  /// Writes a diagnostic message to stderr.
  ///
  /// MCP protocol traffic uses stdout; logging to stdout would corrupt the
  /// JSON-RPC stream consumed by clients.
  private static func write(_ message: String) {
    guard let data = "\(message)\n".data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
  }
}
