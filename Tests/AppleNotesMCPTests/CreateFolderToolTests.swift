import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Create Folder Tool")
struct CreateFolderToolTests {
  @Test
  func executeReturnsCreatedPayloadForScopedFolderPath() async throws {
    let tool = Tool.CreateFolder { _ in
      StaticCreateFolderExecutor(
        account: "iCloud",
        path: "Work/Projects/2026",
        name: "2026",
        parentPath: "Work/Projects",
        depth: 2,
        alreadyExisted: false
      )
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateFolder.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Work/Projects/2026")
        ]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload == .init(
      account: "iCloud",
      path: "Work/Projects/2026",
      name: "2026",
      parentPath: "Work/Projects",
      depth: 2,
      alreadyExisted: false
    ))
  }

  @Test
  func executeBuildsScopedScriptForNestedPath() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.CreateFolder { source in
      sourceStore.set(source)
      return StaticCreateFolderExecutor(
        account: "iCloud",
        path: "Jokes/IT/Deep",
        name: "Deep",
        parentPath: "Jokes/IT",
        depth: 2,
        alreadyExisted: false
      )
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateFolder.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Jokes/IT/Deep")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set fullPath to \"Jokes/IT/Deep\""))
    #expect(source.contains("set pathSegments to {\"Jokes\", \"IT\", \"Deep\"}"))
    #expect(source.contains("set alreadyExistedFlag to 1"))
    #expect(source.contains("make new folder at currentFolder with properties {name:segmentValue}"))
    #expect(source.contains("return {accountName, fullPath, leafName, parentPath, depthValue, alreadyExistedFlag}"))
  }

  @Test
  func executeBuildsCrossAccountScriptWhenAccountIsOmitted() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.CreateFolder { source in
      sourceStore.set(source)
      return StaticCreateFolderExecutor(
        account: "iCloud",
        path: "Work/Projects/2026",
        name: "2026",
        parentPath: "Work/Projects",
        depth: 2,
        alreadyExisted: false
      )
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateFolder.name,
        arguments: [
          "folder": .string("Work/Projects/2026")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set matchingRoots to {}"))
    #expect(source.contains("set matchingAccounts to {}"))
    #expect(source.contains("set firstSegment to \"Work\""))
    #expect(source.contains("MCP_FOLDER_CREATE_REQUIRES_ACCOUNT::"))
    #expect(source.contains("MCP_FOLDER_AMBIGUOUS::"))
  }

  @Test
  func executeThrowsValidationErrorForMissingFolder() async {
    let tool = Tool.CreateFolder { _ in
      ThrowingCreateFolderExecutor(error: CreateFolderTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateFolder.name,
          arguments: ["account": .string("iCloud")]
        )
      )
      Issue.record("Expected missing folder validation error")
    } catch let error as Error.CreateFolder {
      #expect(error == .missingFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredFolderErrors() async {
    let tool = Tool.CreateFolder { _ in
      ThrowingCreateFolderExecutor(
        error: Error.AppleScript.custom(info: "MCP_FOLDER_AMBIGUOUS::Work::iCloud||On My Mac")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateFolder.name,
          arguments: ["folder": .string("Work/Projects")]
        )
      )
      Issue.record("Expected folder ambiguity mapping")
    } catch let error as Error.FolderResolution {
      #expect(error == .ambiguousFolder(path: "Work", accounts: ["iCloud", "On My Mac"]))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredAccountRequiredForCreationError() async {
    let tool = Tool.CreateFolder { _ in
      ThrowingCreateFolderExecutor(
        error: Error.AppleScript.custom(info: "MCP_FOLDER_CREATE_REQUIRES_ACCOUNT::BrandNew/Projects")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateFolder.name,
          arguments: ["folder": .string("BrandNew/Projects")]
        )
      )
      Issue.record("Expected account-required-for-creation mapping")
    } catch let error as Error.FolderResolution {
      #expect(error == .accountRequiredForCreation(path: "BrandNew/Projects"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.CreateFolder { _ in
      InvalidCreateFolderExecutor()
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateFolder.name,
          arguments: ["folder": .string("Work/Projects")]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.CreateFolder {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.CreateFolderResult {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode(Models.CreateFolderResult.self, from: data)
  }
}

private struct StaticCreateFolderExecutor: AppleScriptExecuting {
  let account: String
  let path: String
  let name: String
  let parentPath: String
  let depth: Int
  let alreadyExisted: Bool

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: account), at: 1)
    descriptor.insert(NSAppleEventDescriptor(string: path), at: 2)
    descriptor.insert(NSAppleEventDescriptor(string: name), at: 3)
    descriptor.insert(NSAppleEventDescriptor(string: parentPath), at: 4)
    descriptor.insert(NSAppleEventDescriptor(int32: Int32(depth)), at: 5)
    descriptor.insert(NSAppleEventDescriptor(int32: alreadyExisted ? 1 : 0), at: 6)
    return descriptor
  }
}

private struct InvalidCreateFolderExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct ThrowingCreateFolderExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct CreateFolderTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
