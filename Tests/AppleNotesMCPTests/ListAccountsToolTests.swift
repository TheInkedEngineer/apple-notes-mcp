import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("List Accounts Tool")
struct ListAccountsToolTests {
  @Test
  func executeReturnsAccountsSortedByName() async throws {
    let tool = Tool.ListAccounts { _ in
      StaticAccountsExecutor(accounts: ["On My Mac", "iCloud"])
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(name: Tool.ListAccounts.name)
    )

    #expect(result.isError == false)
    let accounts = try decodeAccounts(from: result)
    #expect(accounts.map(\.name) == ["iCloud", "On My Mac"])
  }

  @Test
  func executeHandlesSingleAccountStringDescriptor() async throws {
    let tool = Tool.ListAccounts { _ in
      SingleAccountStringExecutor(name: "iCloud")
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(name: Tool.ListAccounts.name)
    )

    let accounts = try decodeAccounts(from: result)
    #expect(accounts.map(\.name) == ["iCloud"])
  }

  @Test
  func executePropagatesScriptErrors() async {
    let tool = Tool.ListAccounts { _ in
      ThrowingListAccountsExecutor(error: ListAccountsToolTestError(message: "script failed"))
    }

    await #expect(throws: ListAccountsToolTestError.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(name: Tool.ListAccounts.name)
      )
    }
  }

  private func decodeAccounts(from result: CallTool.Result) throws -> [Models.Account] {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode([Models.Account].self, from: data)
  }
}

private struct StaticAccountsExecutor: AppleScriptExecuting {
  let accounts: [String]

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    DescriptorBuilders.makeAccountsDescriptor(accounts)
  }
}

private struct SingleAccountStringExecutor: AppleScriptExecuting {
  let name: String

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor(string: name)
  }
}

private struct ThrowingListAccountsExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct ListAccountsToolTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
