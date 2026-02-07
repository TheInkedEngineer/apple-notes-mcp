import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("List Folders Tool")
struct ListFoldersToolTests {
  @Test
  func executeReturnsFoldersSortedByAccountThenPath() async throws {
    let tool = Tool.ListFolders { _ in
      StaticFoldersExecutor(folders: [
        .init(account: "On My Mac", path: "Archive", name: "Archive", parentPath: "", depth: 0),
        .init(account: "iCloud", path: "Work/Projects", name: "Projects", parentPath: "Work", depth: 1),
        .init(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)
      ])
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(name: Tool.ListFolders.name)
    )

    #expect(result.isError == false)
    let folders = try decodeFolders(from: result)
    #expect(folders.map(\.account) == ["iCloud", "iCloud", "On My Mac"])
    #expect(folders.map(\.path) == ["Work", "Work/Projects", "Archive"])
    #expect(folders[0].parentPath == "")
    #expect(folders[1].parentPath == "Work")
  }

  @Test
  func executeBuildsScopedScriptUsingTrimmedAccount() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.ListFolders { source in
      sourceStore.set(source)
      return StaticFoldersExecutor(folders: [])
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListFolders.name,
        arguments: ["account": .string("  iCloud  ")]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set requestedAccount to \"iCloud\""))
    #expect(source.contains(FolderScriptErrorPrefix.accountNotFound))
    #expect(source.contains("repeat with folderRef in every folder of targetAccount"))
    #expect(source.contains("set pathSegments to {leafName}"))
    #expect(source.contains("if (class of parentContainer is account) then"))
  }

  @Test
  func executeThrowsValidationErrorForInvalidAccountType() async {
    let tool = Tool.ListFolders { _ in
      ThrowingListFoldersExecutor(error: ListFoldersToolTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListFolders.name,
          arguments: ["account": .int(1)]
        )
      )
      Issue.record("Expected account type validation error")
    } catch let error as Error.ListFoldersQuery {
      #expect(error == .invalidAccountType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyAccount() async {
    let tool = Tool.ListFolders { _ in
      ThrowingListFoldersExecutor(error: ListFoldersToolTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListFolders.name,
          arguments: ["account": .string("   ")]
        )
      )
      Issue.record("Expected empty account validation error")
    } catch let error as Error.ListFoldersQuery {
      #expect(error == .emptyAccount)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredAccountErrorFromScript() async {
    let tool = Tool.ListFolders { _ in
      ThrowingListFoldersExecutor(
        error: Error.AppleScript.custom(info: "MCP_ACCOUNT_NOT_FOUND::iCloud")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListFolders.name,
          arguments: ["account": .string("iCloud")]
        )
      )
      Issue.record("Expected mapped account error")
    } catch let error as Error.FolderResolution {
      #expect(error == .accountNotFound("iCloud"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executePropagatesUnknownScriptErrors() async {
    let tool = Tool.ListFolders { _ in
      ThrowingListFoldersExecutor(error: ListFoldersToolTestError(message: "script failed"))
    }

    await #expect(throws: ListFoldersToolTestError.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(name: Tool.ListFolders.name)
      )
    }
  }

  private func decodeFolders(from result: CallTool.Result) throws -> [Models.Folder] {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode([Models.Folder].self, from: data)
  }
}

private struct StaticFoldersExecutor: AppleScriptExecuting {
  let folders: [FolderDescriptorInput]

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    DescriptorBuilders.makeFoldersDescriptor(folders)
  }
}

private struct ThrowingListFoldersExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct ListFoldersToolTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
