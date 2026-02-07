import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@Suite("Server Integration")
struct ServerIntegrationSmokeTests {
  @Test
  func serverListsRegisteredToolsExecutesKnownCallAndHandlesUnknownCall() async throws {
    let config = Models.AppConfig.default
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [IntegrationEchoTool()],
      permissionChecker: AllowPermissionChecker()
    )

    let server = Server(
      name: config.name,
      version: config.version,
      capabilities: .init(tools: .init(listChanged: config.listChanged))
    )

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: registry.allTools())
    }

    await server.withMethodHandler(CallTool.self) { params in
      try await registry.execute(tool: params.name, using: params)
    }

    let transports = await InMemoryTransport.createConnectedPair()
    let client = Client(name: "integration-test-client", version: "1.0.0")

    try await server.start(transport: transports.server)

    do {
      _ = try await client.connect(transport: transports.client)

      let listed = try await client.listTools()
      #expect(listed.nextCursor == nil)
      #expect(listed.tools.map(\.name) == [IntegrationEchoTool.name])

      let echoCall = try await client.callTool(name: IntegrationEchoTool.name)
      #expect(echoCall.isError == false)
      #expect(ResultHelpers.firstText(in: echoCall.content) == #"{"ok":true}"#)

      let unknownCall = try await client.callTool(name: "missing_tool")
      #expect(unknownCall.isError == true)
      #expect(ResultHelpers.firstText(in: unknownCall.content) == "Unknown tool: missing_tool")
    } catch {
      await client.disconnect()
      await server.stop()
      await server.waitUntilCompleted()
      throw error
    }

    await client.disconnect()
    await server.stop()
    await server.waitUntilCompleted()
  }
}

private struct AllowPermissionChecker: PermissionChecking {
  @MainActor
  func ensurePermission() throws(Error.SystemSettings) {}
}

private struct IntegrationEchoTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "integration_echo"
  static let description = "Echo probe for server integration smoke test."
  static let inputSchema: MCP.Value = .object([
    "type": "object",
    "additionalProperties": false
  ])

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    .init(content: [.text(#"{"ok":true}"#)], isError: false)
  }
}
