import Foundation
import MCP

/// Namespace for MCP tool implementations and related shared contracts.
enum Tool {}

extension Tool {
  /// Common protocol implemented by each MCP tool in this server.
  protocol Blueprint: Sendable {
    /// Stable MCP tool name.
    static var name: String { get }
    /// Human-readable description shown to MCP clients.
    static var description: String { get }
    /// JSON Schema-like MCP value describing accepted input.
    static var inputSchema: Value { get }

    /// Executes tool business logic for an incoming tool call.
    func execute(using params: CallTool.Parameters) async throws -> CallTool.Result
  }
}
