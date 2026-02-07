import Foundation

/// Shared script prefix contract for folder-related AppleScript errors.
enum FolderScriptErrorPrefix {
  static let accountNotFound = "MCP_ACCOUNT_NOT_FOUND::"
  static let folderNotFound = "MCP_FOLDER_NOT_FOUND::"
  static let folderAmbiguous = "MCP_FOLDER_AMBIGUOUS::"
  static let accountRequiredForCreation = "MCP_FOLDER_CREATE_REQUIRES_ACCOUNT::"
  static let accountSeparator = "||"
}

enum FolderScriptErrorMapper {
  /// Maps structured AppleScript failures to shared folder errors.
  static func map(_ error: any Swift.Error) -> Error.FolderResolution? {
    guard let scriptError = error as? Error.AppleScript else {
      return nil
    }
    guard case let .custom(info) = scriptError else {
      return nil
    }

    if let payload = ScriptErrorPayload.extract(after: FolderScriptErrorPrefix.accountNotFound, in: info) {
      return .accountNotFound(payload)
    }

    if let payload = ScriptErrorPayload.extract(after: FolderScriptErrorPrefix.folderNotFound, in: info) {
      let parts = payload.components(separatedBy: "::")
      if parts.count >= 2 {
        let segment = parts[0]
        let path = parts.dropFirst().joined(separator: "::")
        return .folderNotFound(segment: segment, path: path)
      }
      return .folderNotFound(segment: payload, path: payload)
    }

    if let payload = ScriptErrorPayload.extract(after: FolderScriptErrorPrefix.folderAmbiguous, in: info) {
      let parts = payload.components(separatedBy: "::")
      guard parts.count >= 2 else {
        return nil
      }

      let path = parts[0]
      let accountsRaw = parts.dropFirst().joined(separator: "::")
      let accounts = accountsRaw
        .components(separatedBy: FolderScriptErrorPrefix.accountSeparator)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

      return .ambiguousFolder(path: path, accounts: accounts)
    }

    if let payload = ScriptErrorPayload.extract(after: FolderScriptErrorPrefix.accountRequiredForCreation, in: info) {
      return .accountRequiredForCreation(path: payload)
    }

    return nil
  }
}
