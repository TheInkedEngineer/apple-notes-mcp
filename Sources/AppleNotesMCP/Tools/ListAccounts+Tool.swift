import Foundation
import MCP

extension Tool {
  /// `list_accounts` returns all Apple Notes account names.
  struct ListAccounts: Blueprint {

    // MARK: Properties

    static let name: String = "list_accounts"

    static let description: String = "List all Apple Notes account names."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "additionalProperties": false
    ])

    private let appleScriptFactory: @Sendable (String) -> any AppleScriptExecuting

    /// Injects the AppleScript execution factory.
    init(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting = { source in
        AppleScript(source: source)
      }
    ) {
      self.appleScriptFactory = appleScriptFactory
    }

    // MARK: Functions

    /// Lists available Notes accounts and returns a stable sorted payload.
    ///
    /// Sorting is case-insensitive to keep response ordering deterministic.
    func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
      let executor = appleScriptFactory(Self.script)

      let accounts = try await MainActor.run {
        let descriptor = try executor.run()
        return descriptor.parseAccounts()
      }
      let sortedAccounts = accounts.sorted { lhs, rhs in
        let lhsKey = lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let rhsKey = rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if lhsKey == rhsKey {
          return lhs.name < rhs.name
        }
        return lhsKey < rhsKey
      }

      let payload = try sortedAccounts.mcpPayload()
      return .init(content: [.text(payload)], isError: false)
    }

    // MARK: Script

    private static let script = """
    tell application "Notes"
        return name of every account
    end tell
    """
  }
}
