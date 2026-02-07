import MCP

public enum ResultHelpers {
  public static func firstText(in result: CallTool.Result) -> String? {
    guard case let .text(text)? = result.content.first else {
      return nil
    }
    return text
  }

  public static func firstText(in content: [MCP.Tool.Content]) -> String? {
    guard case let .text(text)? = content.first else {
      return nil
    }
    return text
  }
}
