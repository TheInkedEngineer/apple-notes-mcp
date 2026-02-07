import Foundation
import MCP

/// Parsed folder path components used by folder-aware tools.
struct FolderPath: Sendable, Equatable {
  let fullPath: String
  let segments: [String]

  init(fullPath: String, segments: [String]) {
    precondition(!segments.isEmpty, "FolderPath requires at least one segment.")
    self.fullPath = fullPath
    self.segments = segments
  }

  var leafName: String {
    segments[segments.count - 1]
  }
}

/// Parsed account/folder selection shared by folder-aware tools.
struct FolderSelection: Sendable, Equatable {
  let account: String?
  let folderPath: FolderPath?
}

enum FolderResolution {
  /// Parses optional `account` + `folder` arguments into a structured selection.
  static func parseOptionalFolderSelection(
    from arguments: [String: MCP.Value]?
  ) throws(Error.FolderResolution) -> FolderSelection? {
    let parsedAccount = try parseAccount(from: arguments)
    let parsedFolder = try parseFolderPath(from: arguments)

    if parsedAccount == nil, parsedFolder == nil {
      return nil
    }

    return FolderSelection(account: parsedAccount, folderPath: parsedFolder)
  }

  /// Parses optional account text.
  private static func parseAccount(from arguments: [String: MCP.Value]?) throws(Error.FolderResolution) -> String? {
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

  /// Parses optional folder path text.
  private static func parseFolderPath(from arguments: [String: MCP.Value]?) throws(Error.FolderResolution) -> FolderPath? {
    guard let rawFolder = arguments?["folder"] else {
      return nil
    }

    guard let folderValue = rawFolder.stringValue else {
      throw .invalidFolderType
    }

    let trimmedPath = folderValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else {
      throw .emptyFolder
    }

    return try parseFolderPathString(trimmedPath)
  }

  /// Parses validated folder path text into path segments.
  static func parseFolderPathString(_ path: String) throws(Error.FolderResolution) -> FolderPath {
    if path.hasPrefix("/") || path.hasSuffix("/") {
      throw .invalidFolderPathFormat(path)
    }

    let segments = path
      .split(separator: "/", omittingEmptySubsequences: false)
      .map { segment in
        segment.trimmingCharacters(in: .whitespacesAndNewlines)
      }

    guard !segments.isEmpty, segments.allSatisfy({ !$0.isEmpty }) else {
      throw .invalidFolderPathFormat(path)
    }

    let canonicalPath = segments.joined(separator: "/")
    return FolderPath(fullPath: canonicalPath, segments: segments)
  }
}
