import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Rename Folder Tool")
struct RenameFolderToolTests {
  @Test
  func executeReturnsRenamedPayloadForScopedFolderPath() async throws {
    let tool = Tool.RenameFolder { _ in
      StaticRenameFolderExecutor(
        account: "iCloud",
        oldPath: "Work/Projects",
        newPath: "Work/Roadmap",
        name: "Roadmap",
        parentPath: "Work",
        depth: 1,
        renamed: true
      )
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.RenameFolder.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Work/Projects"),
          "newName": .string("Roadmap")
        ]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload == .init(
      account: "iCloud",
      oldPath: "Work/Projects",
      newPath: "Work/Roadmap",
      name: "Roadmap",
      parentPath: "Work",
      depth: 1,
      renamed: true
    ))
  }

  @Test
  func executeBuildsScopedScriptForNestedPath() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.RenameFolder { source in
      sourceStore.set(source)
      return StaticRenameFolderExecutor(
        account: "iCloud",
        oldPath: "Jokes/IT/Deep",
        newPath: "Jokes/IT/Archive",
        name: "Archive",
        parentPath: "Jokes/IT",
        depth: 2,
        renamed: true
      )
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.RenameFolder.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Jokes/IT/Deep"),
          "newName": .string("Archive")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set fullPath to \"Jokes/IT/Deep\""))
    #expect(source.contains("set pathSegments to {\"Jokes\", \"IT\", \"Deep\"}"))
    #expect(source.contains("MCP_CANNOT_MODIFY_SYSTEM_FOLDER::"))
    #expect(source.contains("MCP_FOLDER_NAME_CONFLICT::"))
  }

  @Test
  func executeBuildsCrossAccountScriptWhenAccountIsOmitted() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.RenameFolder { source in
      sourceStore.set(source)
      return StaticRenameFolderExecutor(
        account: "iCloud",
        oldPath: "Archive/Ideas",
        newPath: "Archive/Backlog",
        name: "Backlog",
        parentPath: "Archive",
        depth: 1,
        renamed: true
      )
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.RenameFolder.name,
        arguments: [
          "folder": .string("Archive/Ideas"),
          "newName": .string("Backlog")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set matchingFolders to {}"))
    #expect(source.contains("set fullPath to \"Archive/Ideas\""))
    #expect(source.contains("set newName to \"Backlog\""))
  }

  @Test
  func executeThrowsValidationErrorForMissingFolder() async {
    let tool = Tool.RenameFolder { _ in
      ThrowingRenameFolderExecutor(error: RenameFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.RenameFolder.name,
          arguments: ["newName": .string("Roadmap")]
        )
      )
      Issue.record("Expected missing folder validation error")
    } catch let error as Error.RenameFolder {
      #expect(error == .missingFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidNewNameWithSlash() async {
    let tool = Tool.RenameFolder { _ in
      ThrowingRenameFolderExecutor(error: RenameFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.RenameFolder.name,
          arguments: [
            "folder": .string("Work/Projects"),
            "newName": .string("Bad/Name")
          ]
        )
      )
      Issue.record("Expected invalid newName format validation error")
    } catch let error as Error.RenameFolder {
      #expect(error == .invalidNewNameContainsPathSeparator)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsSystemFolderProtectionError() async {
    let tool = Tool.RenameFolder { _ in
      ThrowingRenameFolderExecutor(
        error: Error.AppleScript.custom(info: "MCP_CANNOT_MODIFY_SYSTEM_FOLDER::Notes")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.RenameFolder.name,
          arguments: [
            "folder": .string("Notes"),
            "newName": .string("Notes-Old")
          ]
        )
      )
      Issue.record("Expected system folder protection mapping")
    } catch let error as Error.RenameFolder {
      #expect(error == .cannotModifySystemFolder("Notes"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsFolderNameConflictError() async {
    let tool = Tool.RenameFolder { _ in
      ThrowingRenameFolderExecutor(
        error: Error.AppleScript.custom(info: "MCP_FOLDER_NAME_CONFLICT::Roadmap")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.RenameFolder.name,
          arguments: [
            "folder": .string("Work/Projects"),
            "newName": .string("Roadmap")
          ]
        )
      )
      Issue.record("Expected folder-name-conflict mapping")
    } catch let error as Error.RenameFolder {
      #expect(error == .folderNameConflict("Roadmap"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.RenameFolder { _ in
      InvalidRenameFolderExecutor()
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.RenameFolder.name,
          arguments: [
            "folder": .string("Work/Projects"),
            "newName": .string("Roadmap")
          ]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.RenameFolder {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.RenameFolderResult {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode(Models.RenameFolderResult.self, from: data)
  }
}

private struct StaticRenameFolderExecutor: AppleScriptExecuting {
  let account: String
  let oldPath: String
  let newPath: String
  let name: String
  let parentPath: String
  let depth: Int
  let renamed: Bool

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: account), at: 1)
    descriptor.insert(NSAppleEventDescriptor(string: oldPath), at: 2)
    descriptor.insert(NSAppleEventDescriptor(string: newPath), at: 3)
    descriptor.insert(NSAppleEventDescriptor(string: name), at: 4)
    descriptor.insert(NSAppleEventDescriptor(string: parentPath), at: 5)
    descriptor.insert(NSAppleEventDescriptor(int32: Int32(depth)), at: 6)
    descriptor.insert(NSAppleEventDescriptor(int32: renamed ? 1 : 0), at: 7)
    return descriptor
  }
}

private struct InvalidRenameFolderExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct ThrowingRenameFolderExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct RenameFolderTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
