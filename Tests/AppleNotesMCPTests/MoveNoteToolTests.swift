import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Move Note Tool")
struct MoveNoteToolTests {
  @Test
  func executeReturnsMovePayloadForScopedDestination() async throws {
    let tool = Tool.MoveNote { _ in
      StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "iCloud",
        path: "Work/Projects",
        folder: "Projects"
      ))
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "account": .string("iCloud"),
          "folder": .string("Work/Projects")
        ]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload.id == "note-123")
    #expect(payload.account == "iCloud")
    #expect(payload.path == "Work/Projects")
    #expect(payload.folder == "Projects")
  }

  @Test
  func executeBuildsScopedScriptForNestedFolderPath() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "iCloud",
        path: "Jokes/IT/Deep",
        folder: "Deep"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "account": .string("iCloud"),
          "folder": .string("Jokes/IT/Deep")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set fullPath to \"Jokes/IT/Deep\""))
    #expect(source.contains("set pathSegments to {\"Jokes\", \"IT\", \"Deep\"}"))
    #expect(source.contains("move n to currentFolder"))
  }

  @Test
  func executeBuildsCrossAccountScriptWhenAccountIsOmitted() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "On My Mac",
        path: "Archive",
        folder: "Archive"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "folder": .string("Archive")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set matchingFolders to {}"))
    #expect(source.contains("set fullPath to \"Archive\""))
    #expect(source.contains("move n to targetFolder"))
  }

  @Test
  func executeThrowsValidationErrorForMissingID() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: MoveNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: ["folder": .string("Work")]
        )
      )
      Issue.record("Expected missing id validation error")
    } catch let error as Error.MoveNote {
      #expect(error == .missingID)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDType() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: MoveNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: [
            "id": .int(1),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected invalid id validation error")
    } catch let error as Error.MoveNote {
      #expect(error == .invalidIDType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyID() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: MoveNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: [
            "id": .string("   "),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected empty id validation error")
    } catch let error as Error.MoveNote {
      #expect(error == .emptyID)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorWhenFolderIsMissing() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: MoveNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: ["id": .string("note-123")]
        )
      )
      Issue.record("Expected missing folder validation error")
    } catch let error as Error.MoveNote {
      #expect(error == .missingFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorWhenAccountProvidedWithoutFolder() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: MoveNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: [
            "id": .string("note-123"),
            "account": .string("iCloud")
          ]
        )
      )
      Issue.record("Expected missing folder validation error")
    } catch let error as Error.MoveNote {
      #expect(error == .missingFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredNoteNotFoundError() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: Error.AppleScript.custom(info: "MCP_NOTE_NOT_FOUND::missing-id"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: [
            "id": .string("missing-id"),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected note-not-found mapping")
    } catch let error as Error.MoveNote {
      #expect(error == .noteNotFound("missing-id"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredFolderErrors() async {
    let tool = Tool.MoveNote { _ in
      ThrowingMoveNoteExecutor(error: Error.AppleScript.custom(info: "MCP_FOLDER_NOT_FOUND::Work::Work"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: [
            "id": .string("note-123"),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected folder error mapping")
    } catch let error as Error.FolderResolution {
      #expect(error == .folderNotFound(segment: "Work", path: "Work"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.MoveNote { _ in
      InvalidMoveNoteExecutor()
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.MoveNote.name,
          arguments: [
            "id": .string("note-123"),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.MoveNote {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  // MARK: - Cross-Account Fallback

  @Test
  func scopedScriptContainsCrossAccountDetection() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "iCloud",
        path: "Work",
        folder: "Work"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "account": .string("iCloud"),
          "folder": .string("Work")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set isSameAccount to false"))
    #expect(source.contains("first note of targetAccount whose id is noteID"))
  }

  @Test
  func scopedScriptContainsCrossAccountFallback() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "iCloud",
        path: "Work",
        folder: "Work"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "account": .string("iCloud"),
          "folder": .string("Work")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("make new note at currentFolder with properties"))
    #expect(source.contains("delete n"))
    #expect(source.contains("set originalBody"))
  }

  @Test
  func unscopedScriptContainsCrossAccountDetection() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "On My Mac",
        path: "Archive",
        folder: "Archive"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "folder": .string("Archive")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set isSameAccount to false"))
    #expect(source.contains("first note of destAccount whose id is noteID"))
  }

  @Test
  func unscopedScriptContainsCrossAccountFallback() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "On My Mac",
        path: "Archive",
        folder: "Archive"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "folder": .string("Archive")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("make new note at targetFolder with properties"))
    #expect(source.contains("delete n"))
    #expect(source.contains("set originalBody"))
  }

  // MARK: - Cross-Account Folder Auto-Creation

  @Test
  func scopedScriptContainsCrossAccountFolderCreation() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "Google",
        path: "Feedback",
        folder: "Feedback"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "account": .string("Google"),
          "folder": .string("Feedback")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("make new folder at targetAccount with properties"))
    #expect(source.contains("make new folder at currentFolder with properties"))
  }

  @Test
  func unscopedScriptDoesNotContainFolderCreation() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.MoveNote { source in
      sourceStore.set(source)
      return StaticMoveNoteExecutor(input: .init(
        id: "note-123",
        title: "Quarterly Plan",
        account: "On My Mac",
        path: "Archive",
        folder: "Archive"
      ))
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.MoveNote.name,
        arguments: [
          "id": .string("note-123"),
          "folder": .string("Archive")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(!source.contains("make new folder"))
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.MoveNoteResult {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode(Models.MoveNoteResult.self, from: data)
  }
}

private struct StaticMoveNoteExecutor: AppleScriptExecuting {
  let input: MoveResultDescriptorInput

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: input.id), at: 1)
    descriptor.insert(NSAppleEventDescriptor(string: input.title), at: 2)
    descriptor.insert(NSAppleEventDescriptor(string: input.account), at: 3)
    descriptor.insert(NSAppleEventDescriptor(string: input.path), at: 4)
    descriptor.insert(NSAppleEventDescriptor(string: input.folder), at: 5)
    descriptor.insert(NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 0)), at: 6)
    return descriptor
  }
}

private struct ThrowingMoveNoteExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct InvalidMoveNoteExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct MoveNoteTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}

private struct MoveResultDescriptorInput: Sendable {
  let id: String
  let title: String
  let account: String
  let path: String
  let folder: String
}
