import Foundation
import MCP

extension Tool {
  /// Maps tool names to implementations and centralizes execution concerns.
  ///
  /// Responsibilities:
  /// - expose tool metadata for `tools/list`
  /// - resolve tool by name for `tools/call`
  /// - enforce permission checks before execution
  /// - normalize non-cancellation failures into MCP error results
  struct Registry: Sendable {
    static let `default` = Self(
      tools: [
        Tool.BatchDeleteNotes(),
        Tool.BatchGetNotes(),
        Tool.CreateFolder(),
        Tool.CreateNote(),
        Tool.DeleteFolder(),
        Tool.DeleteNote(),
        Tool.GetNote(),
        Tool.ListAccounts(),
        Tool.ListFolders(),
        Tool.ListNotes(),
        Tool.MoveFolder(),
        Tool.MoveNote(),
        Tool.RenameFolder(),
        Tool.UpdateNote()
      ],
      permissionChecker: SystemPermissionChecker()
    )
    
    private let toolsByName: [String: Tool.Blueprint]
    private let permissionChecker: any PermissionChecking
    
    /// Builds registry index and injects shared permission gate.
    ///
    /// If duplicate tool names are provided, the later entry wins by dictionary
    /// overwrite. This keeps registry construction deterministic in tests.
    init(
      tools: [Tool.Blueprint],
      permissionChecker: any PermissionChecking = SystemPermissionChecker()
    ) {
      self.permissionChecker = permissionChecker
      self.toolsByName = tools.reduce(into: [String: Tool.Blueprint]()) { dict, new in
        dict[type(of: new).name] = new
      }
    }
    
    /// Returns all tools sorted by name for stable client presentation.
    func allTools() -> [MCP.Tool] {
      toolsByName.values
        .sorted { type(of: $0).name < type(of: $1).name }
        .map { blueprint in
          MCP.Tool(
            name: type(of: blueprint).name,
            description: type(of: blueprint).description,
            inputSchema: type(of: blueprint).inputSchema
          )
        }
    }
    
    /// Resolves a tool by name and converts failures to MCP errors.
    ///
    /// `CancellationError` is rethrown to preserve shutdown behavior.
    func execute(tool name: String, using params: CallTool.Parameters) async throws -> CallTool.Result {
      guard let tool = toolsByName[name] else {
        return .init(content: [.text("Unknown tool: \(name)")], isError: true)
      }
      
      do {
        try await permissionChecker.ensurePermission()
        return try await tool.execute(using: params)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return .init(content: [.text(message)], isError: true)
      }
    }
  }
}
