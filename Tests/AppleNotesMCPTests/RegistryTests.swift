import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@Suite("Tool Registry")
struct RegistryTests {
  @Test
  func allToolsReturnsEmptyWhenNoToolsRegistered() {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [],
      permissionChecker: AllowPermissionChecker()
    )

    #expect(registry.allTools().isEmpty)
  }

  @Test
  func allToolsReturnsToolsSortedByName() {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [ZetaRegistryTool(), AlphaRegistryTool()],
      permissionChecker: AllowPermissionChecker()
    )

    let toolNames = registry.allTools().map(\.name)
    #expect(toolNames == ["alpha_tool", "zeta_tool"])
  }

  @Test
  func defaultRegistryContainsAllExpectedTools() {
    let toolNames = Tool.Registry.default.allTools().map(\.name)
    #expect(toolNames == ["batch_delete_notes", "batch_get_notes", "create_folder", "create_note", "delete_folder", "delete_note", "get_note", "list_accounts", "list_folders", "list_notes", "move_folder", "move_note", "rename_folder", "update_note"])
  }

  @Test
  func unknownToolBypassesPermissionCheckAndReturnsUnknownToolError() async throws {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [AlphaRegistryTool()],
      permissionChecker: ThrowPermissionChecker(error: .missingUserConsent)
    )

    let result = try await registry.execute(
      tool: "missing_tool",
      using: CallToolParameterFactory.make(name: "missing_tool")
    )

    #expect(result.isError == true)
    #expect(ResultHelpers.firstText(in: result) == "Unknown tool: missing_tool")
  }

  @Test
  func permissionFailureReturnsMCPErrorResponse() async throws {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [AlphaRegistryTool()],
      permissionChecker: ThrowPermissionChecker(error: .missingUserConsent)
    )

    let result = try await registry.execute(
      tool: AlphaRegistryTool.name,
      using: CallToolParameterFactory.make(name: AlphaRegistryTool.name)
    )

    #expect(result.isError == true)
    #expect(ResultHelpers.firstText(in: result)?.contains("Automation permission for Apple Notes") == true)
  }

  @Test
  func permissionFailurePreventsToolExecution() async throws {
    let counter = InvocationCounter()
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [CountingTool(counter: counter)],
      permissionChecker: ThrowPermissionChecker(error: .missingUserConsent)
    )

    _ = try await registry.execute(
      tool: CountingTool.name,
      using: CallToolParameterFactory.make(name: CountingTool.name)
    )

    let count = await counter.value()
    #expect(count == 0)
  }

  @Test
  func toolErrorIsMappedToErrorResult() async throws {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [ThrowingTool()],
      permissionChecker: AllowPermissionChecker()
    )

    let result = try await registry.execute(
      tool: ThrowingTool.name,
      using: CallToolParameterFactory.make(name: ThrowingTool.name)
    )

    #expect(result.isError == true)
    #expect(ResultHelpers.firstText(in: result) == "tool failed")
  }

  @Test
  func cancellationErrorIsRethrown() async {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [CancellationTool()],
      permissionChecker: AllowPermissionChecker()
    )

    await #expect(throws: CancellationError.self) {
      _ = try await registry.execute(
        tool: CancellationTool.name,
        using: CallToolParameterFactory.make(name: CancellationTool.name)
      )
    }
  }

  @Test
  func toolCanReturnExistingErrorResultWithoutAdditionalWrapping() async throws {
    let registry = AppleNotesMCP.Tool.Registry(
      tools: [PassthroughErrorTool()],
      permissionChecker: AllowPermissionChecker()
    )

    let result = try await registry.execute(
      tool: PassthroughErrorTool.name,
      using: CallToolParameterFactory.make(name: PassthroughErrorTool.name)
    )

    #expect(result.isError == true)
    #expect(ResultHelpers.firstText(in: result) == "already formatted")
  }
}

private struct AllowPermissionChecker: PermissionChecking {
  @MainActor
  func ensurePermission() throws(Error.SystemSettings) {}
}

private struct ThrowPermissionChecker: PermissionChecking {
  let error: Error.SystemSettings

  @MainActor
  func ensurePermission() throws(Error.SystemSettings) {
    throw error
  }
}

private actor InvocationCounter {
  private var count = 0

  func increment() {
    count += 1
  }

  func value() -> Int {
    count
  }
}

private struct RegistryTestError: LocalizedError, Sendable {
  let description: String

  var errorDescription: String? {
    description
  }
}

private struct AlphaRegistryTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "alpha_tool"
  static let description = "Alpha"
  static let inputSchema: Value = .object(["type": "object"])

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    .init(content: [.text("alpha")], isError: false)
  }
}

private struct ZetaRegistryTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "zeta_tool"
  static let description = "Zeta"
  static let inputSchema: Value = .object(["type": "object"])

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    .init(content: [.text("zeta")], isError: false)
  }
}

private struct CountingTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "counting_tool"
  static let description = "Counting"
  static let inputSchema: Value = .object(["type": "object"])

  let counter: InvocationCounter

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    await counter.increment()
    return .init(content: [.text("counted")], isError: false)
  }
}

private struct ThrowingTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "throwing_tool"
  static let description = "Throwing"
  static let inputSchema: Value = .object(["type": "object"])

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    throw RegistryTestError(description: "tool failed")
  }
}

private struct CancellationTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "cancellation_tool"
  static let description = "Cancellation"
  static let inputSchema: Value = .object(["type": "object"])

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    throw CancellationError()
  }
}

private struct PassthroughErrorTool: AppleNotesMCP.Tool.Blueprint {
  static let name = "passthrough_error_tool"
  static let description = "Passthrough"
  static let inputSchema: Value = .object(["type": "object"])

  func execute(using _: CallTool.Parameters) async throws -> CallTool.Result {
    .init(content: [.text("already formatted")], isError: true)
  }
}
