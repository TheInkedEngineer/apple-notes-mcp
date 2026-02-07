import MCP

enum CallToolParameterFactory {
  static func make(
    name: String,
    arguments: [String: Value]? = nil
  ) -> CallTool.Parameters {
    CallTool.Parameters(name: name, arguments: arguments)
  }
}
