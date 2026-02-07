import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Delete Note Tool")
struct DeleteNoteToolTests {
  @Test
  func executeReturnsDeletedPayloadForValidID() async throws {
    let tool = Tool.DeleteNote { _ in
      StaticDeleteNoteExecutor(deletedID: "note-123")
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.DeleteNote.name,
        arguments: ["id": .string("note-123")]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload == .init(id: "note-123", deleted: true))
  }

  @Test
  func executeThrowsValidationErrorForMissingID() async {
    let tool = Tool.DeleteNote { _ in
      ThrowingDeleteNoteExecutor(error: DeleteNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.DeleteNote.name))
      Issue.record("Expected missing id validation error")
    } catch let error as Error.DeleteNote {
      #expect(error == .missingID)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDType() async {
    let tool = Tool.DeleteNote { _ in
      ThrowingDeleteNoteExecutor(error: DeleteNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteNote.name,
          arguments: ["id": .int(1)]
        )
      )
      Issue.record("Expected invalid type validation error")
    } catch let error as Error.DeleteNote {
      #expect(error == .invalidIDType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyID() async {
    let tool = Tool.DeleteNote { _ in
      ThrowingDeleteNoteExecutor(error: DeleteNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteNote.name,
          arguments: ["id": .string("   ")]
        )
      )
      Issue.record("Expected empty id validation error")
    } catch let error as Error.DeleteNote {
      #expect(error == .emptyID)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredNoteNotFoundError() async {
    let tool = Tool.DeleteNote { _ in
      ThrowingDeleteNoteExecutor(
        error: Error.AppleScript.custom(info: "MCP_NOTE_NOT_FOUND::missing-note")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteNote.name,
          arguments: ["id": .string("missing-note")]
        )
      )
      Issue.record("Expected note-not-found mapping")
    } catch let error as Error.DeleteNote {
      #expect(error == .noteNotFound("missing-note"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executePropagatesUnknownScriptErrors() async {
    let tool = Tool.DeleteNote { _ in
      ThrowingDeleteNoteExecutor(error: DeleteNoteTestError(message: "script failed"))
    }

    await #expect(throws: DeleteNoteTestError.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteNote.name,
          arguments: ["id": .string("note-123")]
        )
      )
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.DeleteNote { _ in
      InvalidDeleteNoteExecutor()
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.DeleteNote.name,
          arguments: ["id": .string("note-123")]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.DeleteNote {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeEscapesIDInGeneratedScript() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = Tool.DeleteNote { source in
      sourceStore.set(source)
      return StaticDeleteNoteExecutor(deletedID: "note-123")
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.DeleteNote.name,
        arguments: ["id": .string("x\"\\\\id")]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains(#"set noteID to "x\"\\\\id""#))
    #expect(source.contains(NoteScriptErrorPrefix.noteNotFound))
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.DeleteNoteResult {
    let content = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(content.data(using: .utf8))
    return try JSONDecoder().decode(Models.DeleteNoteResult.self, from: data)
  }
}

private struct StaticDeleteNoteExecutor: AppleScriptExecuting {
  let deletedID: String

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor(string: deletedID)
  }
}

private struct InvalidDeleteNoteExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct ThrowingDeleteNoteExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct DeleteNoteTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
