import Foundation
import MCP

extension Tool {
  /// `list_folders` returns Apple Notes folders as account-scoped paths.
  struct ListFolders: Blueprint {

    // MARK: Properties

    static let name: String = "list_folders"

    static let description: String = "List Apple Notes folders, including nested folders, optionally scoped to one account."

    static let inputSchema: MCP.Value = .object([
      "type": "object",
      "properties": .object([
        "account": .object([
          "type": "string",
          "description": "Optional account name scope (for example: iCloud, On My Mac). Case-sensitive."
        ])
      ]),
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

    /// Lists folders recursively, optionally scoped by account.
    ///
    /// Returns canonical `path` plus convenience fields (`name`, `parentPath`,
    /// `depth`) to simplify consumer logic.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result {
      let account = try Self.parseAccount(arguments: params.arguments)
      let script = Self.script(account: account)
      let executor = appleScriptFactory(script)

      let folders: [Models.Folder]
      do {
        folders = try await MainActor.run {
          let descriptor = try executor.run()
          return descriptor.parseFolders()
        }
      } catch {
        if let mappedError = FolderScriptErrorMapper.map(error) {
          throw mappedError
        }
        throw error
      }

      let sortedFolders = folders.sorted { lhs, rhs in
        let lhsAccount = lhs.account.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let rhsAccount = rhs.account.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if lhsAccount == rhsAccount {
          let lhsPath = lhs.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
          let rhsPath = rhs.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
          if lhsPath == rhsPath {
            return lhs.path < rhs.path
          }
          return lhsPath < rhsPath
        }
        return lhsAccount < rhsAccount
      }

      let payload = try sortedFolders.mcpPayload()
      return .init(content: [.text(payload)], isError: false)
    }

    // MARK: Parsing

    /// Parses optional account scope.
    private static func parseAccount(arguments: [String: MCP.Value]?) throws(Error.ListFoldersQuery) -> String? {
      guard let rawAccount = arguments?["account"] else {
        return nil
      }
      guard let accountValue = rawAccount.stringValue else {
        throw .invalidAccountType
      }
      let trimmedAccount = accountValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedAccount.isEmpty else {
        throw .emptyAccount
      }
      return trimmedAccount
    }

    // MARK: Script

    /// Generates recursive folder listing script.
    ///
    /// The script walks each folder's container chain to build full paths and
    /// depth values without relying on UI ordering behavior.
    private static func script(account: String?) -> String {
      let escapedAccount = account?.escapedForAppleScriptLiteral() ?? ""

      return """
      tell application "Notes"
          set requestedAccount to "\(escapedAccount)"
          set output to {}

          if requestedAccount is "" then
              repeat with acc in accounts
                  set accountName to name of acc as string
                  repeat with folderRef in every folder of acc
                      set leafName to name of folderRef as string
                      set pathSegments to {leafName}
                      set cursor to folderRef

                      repeat
                          set parentContainer to container of cursor
                          if (class of parentContainer is account) then
                              exit repeat
                          end if
                          set beginning of pathSegments to (name of parentContainer as string)
                          set cursor to parentContainer
                      end repeat

                      set previousDelimiters to AppleScript's text item delimiters
                      set AppleScript's text item delimiters to "/"
                      set fullPath to pathSegments as string
                      if (count of pathSegments) > 1 then
                          set parentSegments to items 1 thru -2 of pathSegments
                          set parentPath to parentSegments as string
                      else
                          set parentPath to ""
                      end if
                      set AppleScript's text item delimiters to previousDelimiters

                      set depthValue to (count of pathSegments) - 1
                      set end of output to {accountName, fullPath, leafName, parentPath, depthValue}
                  end repeat
              end repeat
              return output
          end if

          try
              set targetAccount to first account whose name is requestedAccount
          on error
              error "\(FolderScriptErrorPrefix.accountNotFound)" & requestedAccount
          end try

          repeat with folderRef in every folder of targetAccount
              set leafName to name of folderRef as string
              set pathSegments to {leafName}
              set cursor to folderRef

              repeat
                  set parentContainer to container of cursor
                  if (class of parentContainer is account) then
                      exit repeat
                  end if
                  set beginning of pathSegments to (name of parentContainer as string)
                  set cursor to parentContainer
              end repeat

              set previousDelimiters to AppleScript's text item delimiters
              set AppleScript's text item delimiters to "/"
              set fullPath to pathSegments as string
              if (count of pathSegments) > 1 then
                  set parentSegments to items 1 thru -2 of pathSegments
                  set parentPath to parentSegments as string
              else
                  set parentPath to ""
              end if
              set AppleScript's text item delimiters to previousDelimiters

              set depthValue to (count of pathSegments) - 1
              set end of output to {requestedAccount, fullPath, leafName, parentPath, depthValue}
          end repeat

          return output
      end tell
      """
    }
  }
}
