import Foundation
import MCP

extension Tool.MoveFolder {

  /// Closure-based dependency injection for sub-tool operations used by `move_folder`.
  ///
  /// Each closure maps to a sub-tool at the domain-model level, hiding MCP parameter
  /// construction and JSON parsing. Tests replace individual closures while production
  /// uses `makeDefault(appleScriptFactory:)` to wire real tool instances.
  struct Operations: Sendable {
    let listFolders: @Sendable (_ account: String?) async throws -> [Models.Folder]
    let listNotes: @Sendable (_ account: String, _ folderPath: String) async throws -> [Models.Note]
    let createFolder: @Sendable (_ account: String, _ folderPath: String) async throws -> Models.CreateFolderResult
    let moveNote: @Sendable (_ noteID: String, _ account: String, _ folderPath: String) async throws -> Models.MoveNoteResult
    let deleteFolder: @Sendable (_ account: String, _ folderPath: String) async throws -> Models.DeleteFolderResult

    /// Constructs production operations that delegate to real tool instances.
    static func makeDefault(
      appleScriptFactory: @escaping @Sendable (String) -> any AppleScriptExecuting
    ) -> Self {
      Self(
        listFolders: { account in
          let tool = Tool.ListFolders(appleScriptFactory: appleScriptFactory)
          var arguments: [String: MCP.Value] = [:]
          if let account {
            arguments["account"] = .string(account)
          }
          let params = CallTool.Parameters(name: Tool.ListFolders.name, arguments: arguments)
          let result = try await tool.execute(using: params)
          let json = try extractText(from: result, tool: "list_folders")
          let data = try extractData(from: json, tool: "list_folders")
          return try JSONDecoder().decode([Models.Folder].self, from: data)
        },
        listNotes: { account, folderPath in
          let tool = Tool.ListNotes(appleScriptFactory: appleScriptFactory)
          let arguments: [String: MCP.Value] = [
            "account": .string(account),
            "folder": .string(folderPath),
            "limit": .int(0)
          ]
          let params = CallTool.Parameters(name: Tool.ListNotes.name, arguments: arguments)
          let result = try await tool.execute(using: params)
          let json = try extractText(from: result, tool: "list_notes")
          let data = try extractData(from: json, tool: "list_notes")
          return try JSONDecoder().decode([Models.Note].self, from: data)
        },
        createFolder: { account, folderPath in
          let tool = Tool.CreateFolder(appleScriptFactory: appleScriptFactory)
          let arguments: [String: MCP.Value] = [
            "account": .string(account),
            "folder": .string(folderPath)
          ]
          let params = CallTool.Parameters(name: Tool.CreateFolder.name, arguments: arguments)
          let result = try await tool.execute(using: params)
          let json = try extractText(from: result, tool: "create_folder")
          let data = try extractData(from: json, tool: "create_folder")
          return try JSONDecoder().decode(Models.CreateFolderResult.self, from: data)
        },
        moveNote: { noteID, account, folderPath in
          let tool = Tool.MoveNote(appleScriptFactory: appleScriptFactory)
          let arguments: [String: MCP.Value] = [
            "id": .string(noteID),
            "account": .string(account),
            "folder": .string(folderPath)
          ]
          let params = CallTool.Parameters(name: Tool.MoveNote.name, arguments: arguments)
          let result = try await tool.execute(using: params)
          let json = try extractText(from: result, tool: "move_note")
          let data = try extractData(from: json, tool: "move_note")
          return try JSONDecoder().decode(Models.MoveNoteResult.self, from: data)
        },
        deleteFolder: { account, folderPath in
          let tool = Tool.DeleteFolder(appleScriptFactory: appleScriptFactory)
          let arguments: [String: MCP.Value] = [
            "account": .string(account),
            "folder": .string(folderPath),
            "confirmCascadeDelete": .bool(true)
          ]
          let params = CallTool.Parameters(name: Tool.DeleteFolder.name, arguments: arguments)
          let result = try await tool.execute(using: params)
          let json = try extractText(from: result, tool: "delete_folder")
          let data = try extractData(from: json, tool: "delete_folder")
          return try JSONDecoder().decode(Models.DeleteFolderResult.self, from: data)
        }
      )
    }

    /// Extracts the first text content from a `CallTool.Result`.
    private static func extractText(from result: CallTool.Result, tool: String) throws -> String {
      guard case let .text(text) = result.content.first else {
        throw Error.MoveFolder.subToolFailed(tool: tool, reason: "No text content in response.")
      }
      return text
    }

    /// Converts a JSON string to `Data`.
    private static func extractData(from json: String, tool: String) throws -> Data {
      guard let data = json.data(using: .utf8) else {
        throw Error.MoveFolder.subToolFailed(tool: tool, reason: "Invalid UTF-8 in response.")
      }
      return data
    }
  }
}
