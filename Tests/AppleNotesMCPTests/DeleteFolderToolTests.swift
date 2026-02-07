import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Delete Folder Tool")
struct DeleteFolderToolTests {
  @Test
  func executeReturnsDeletedPayloadForScopedFolder() async throws {
    let tool = Tool.DeleteFolder { _ in
      StaticDeleteFolderExecutor(
        account: "iCloud",
        path: "Work/Projects",
        folder: "Projects"
      )
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.DeleteFolder.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Work/Projects"),
          "confirmCascadeDelete": .bool(true)
        ]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload == .init(account: "iCloud", path: "Work/Projects", folder: "Projects", deleted: true))
  }

  @Test
  func executeBuildsScopedScriptForNestedPath() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.DeleteFolder { source in
      sourceStore.set(source)
      return StaticDeleteFolderExecutor(
        account: "iCloud",
        path: "Jokes/IT/Deep",
        folder: "Deep"
      )
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.DeleteFolder.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Jokes/IT/Deep"),
          "confirmCascadeDelete": .bool(true)
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set fullPath to \"Jokes/IT/Deep\""))
    #expect(source.contains("set pathSegments to {\"Jokes\", \"IT\", \"Deep\"}"))
    #expect(source.contains("delete currentFolder"))
    #expect(source.contains("MCP_CANNOT_DELETE_SYSTEM_FOLDER::"))
  }

  @Test
  func executeBuildsCrossAccountScriptWhenAccountIsOmitted() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.DeleteFolder { source in
      sourceStore.set(source)
      return StaticDeleteFolderExecutor(
        account: "On My Mac",
        path: "Archive",
        folder: "Archive"
      )
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.DeleteFolder.name,
        arguments: [
          "folder": .string("Archive"),
          "confirmCascadeDelete": .bool(true)
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set matchingFolders to {}"))
    #expect(source.contains("set fullPath to \"Archive\""))
    #expect(source.contains("delete targetFolder"))
  }

  @Test
  func executeThrowsValidationErrorForMissingFolder() async {
    let tool = Tool.DeleteFolder { _ in
      ThrowingDeleteFolderExecutor(error: DeleteFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: ["confirmCascadeDelete": .bool(true)]
        )
      )
      Issue.record("Expected missing folder validation error")
    } catch let error as Error.DeleteFolder {
      #expect(error == .missingFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForMissingConfirmCascadeDelete() async {
    let tool = Tool.DeleteFolder { _ in
      ThrowingDeleteFolderExecutor(error: DeleteFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: ["folder": .string("Work")]
        )
      )
      Issue.record("Expected missing confirmCascadeDelete validation error")
    } catch let error as Error.DeleteFolder {
      #expect(error == .missingConfirmCascadeDelete)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidConfirmCascadeDeleteType() async {
    let tool = Tool.DeleteFolder { _ in
      ThrowingDeleteFolderExecutor(error: DeleteFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: [
            "folder": .string("Work"),
            "confirmCascadeDelete": .string("true")
          ]
        )
      )
      Issue.record("Expected invalid confirmCascadeDelete type validation error")
    } catch let error as Error.DeleteFolder {
      #expect(error == .invalidConfirmCascadeDeleteType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorWhenConfirmCascadeDeleteIsFalse() async {
    let tool = Tool.DeleteFolder { _ in
      ThrowingDeleteFolderExecutor(error: DeleteFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: [
            "folder": .string("Work"),
            "confirmCascadeDelete": .bool(false)
          ]
        )
      )
      Issue.record("Expected confirmCascadeDelete must be true validation error")
    } catch let error as Error.DeleteFolder {
      #expect(error == .confirmCascadeDeleteMustBeTrue)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredSystemFolderProtectionError() async {
    let tool = Tool.DeleteFolder { _ in
      ThrowingDeleteFolderExecutor(
        error: Error.AppleScript.custom(info: "MCP_CANNOT_DELETE_SYSTEM_FOLDER::Notes")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: [
            "folder": .string("Notes"),
            "confirmCascadeDelete": .bool(true)
          ]
        )
      )
      Issue.record("Expected system folder protection mapping")
    } catch let error as Error.DeleteFolder {
      #expect(error == .cannotDeleteSystemFolder("Notes"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredFolderErrors() async {
    let tool = Tool.DeleteFolder { _ in
      ThrowingDeleteFolderExecutor(
        error: Error.AppleScript.custom(info: "MCP_FOLDER_NOT_FOUND::Projects::Work/Projects")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: [
            "folder": .string("Work/Projects"),
            "confirmCascadeDelete": .bool(true)
          ]
        )
      )
      Issue.record("Expected folder error mapping")
    } catch let error as Error.FolderResolution {
      #expect(error == .folderNotFound(segment: "Projects", path: "Work/Projects"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.DeleteFolder { _ in
      InvalidDeleteFolderExecutor()
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteFolder.name,
          arguments: [
            "folder": .string("Work/Projects"),
            "confirmCascadeDelete": .bool(true)
          ]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.DeleteFolder {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.DeleteFolderResult {
    let content = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(content.data(using: .utf8))
    return try JSONDecoder().decode(Models.DeleteFolderResult.self, from: data)
  }
}

private struct StaticDeleteFolderExecutor: AppleScriptExecuting {
  let account: String
  let path: String
  let folder: String

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: account), at: 1)
    descriptor.insert(NSAppleEventDescriptor(string: path), at: 2)
    descriptor.insert(NSAppleEventDescriptor(string: folder), at: 3)
    return descriptor
  }
}

private struct InvalidDeleteFolderExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct ThrowingDeleteFolderExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct DeleteFolderTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
