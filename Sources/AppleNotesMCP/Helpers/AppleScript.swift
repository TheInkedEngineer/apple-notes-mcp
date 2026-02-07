import Foundation

/// Abstraction for AppleScript execution used by tools.
///
/// This seam allows deterministic unit tests by injecting fake executors.
protocol AppleScriptExecuting: Sendable {
  @MainActor
  func run() throws -> NSAppleEventDescriptor
}

/// Production AppleScript executor backed by `NSAppleScript`.
struct AppleScript: AppleScriptExecuting {
  let source: String
  let executionTimeoutSeconds: Int

  init(source: String, executionTimeoutSeconds: Int = 20) {
    self.source = source
    self.executionTimeoutSeconds = max(1, executionTimeoutSeconds)
  }

  /// Compiles and executes script source on the main actor.
  ///
  /// `NSAppleScript` is not thread-safe, so all interaction is main-actor-isolated.
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    let sourceWithTimeout = wrapSourceWithTimeout(source, seconds: executionTimeoutSeconds)
    guard let script = NSAppleScript(source: sourceWithTimeout) else {
      throw Error.AppleScript.failedToCreate
    }

    var compileError: NSDictionary?
    guard script.compileAndReturnError(&compileError) else {
      throw Error.AppleScript.custom(info: formatErrorInfo(compileError))
    }

    var errorInfo: NSDictionary?
    let result = script.executeAndReturnError(&errorInfo)

    if let errorInfo {
      throw Error.AppleScript.custom(info: formatErrorInfo(errorInfo))
    }

    return result
  }

  private func wrapSourceWithTimeout(_ source: String, seconds: Int) -> String {
    """
    with timeout of \(seconds) seconds
    \(source)
    end timeout
    """
  }

  /// Produces stable, readable diagnostics from AppleScript error dictionaries.
  ///
  /// The first line is the raw AppleScript message when available so structured
  /// prefixes (for example `MCP_*::`) remain parseable by error mappers.
  private func formatErrorInfo(_ errorInfo: NSDictionary?) -> String {
    guard let errorInfo else {
      return "Unknown AppleScript error."
    }

    let message = (errorInfo[NSAppleScript.errorMessage] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let brief = (errorInfo[NSAppleScript.errorBriefMessage] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let numberValue = errorInfo[NSAppleScript.errorNumber]
    let code = (numberValue as? NSNumber)?.intValue
      ?? (numberValue as? Int)

    var lines: [String] = []
    if let message, !message.isEmpty {
      lines.append(message)
    }
    if let brief, !brief.isEmpty, brief != message {
      lines.append("brief: \(brief)")
    }
    if let code {
      lines.append("code: \(code)")
    }
    if let range = (errorInfo[NSAppleScript.errorRange] as? NSValue)?.rangeValue {
      lines.append("range: {\(range.location), \(range.length)}")
    }

    if !lines.isEmpty {
      return lines.joined(separator: "\n")
    }
    return String(describing: errorInfo)
  }
}
