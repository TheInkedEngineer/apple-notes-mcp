import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Get Note Tool")
struct GetNoteToolTests {
  @Test
  func executeReturnsSingleNoteForValidID() async throws {
    let noteInput = NoteDescriptorInput(
      id: "test-note-123",
      title: "Test Note",
      bodyHTML: "<div><h1>Test Note</h1></div><div><br></div><div>Content</div>",
      createdAt: Date(timeIntervalSince1970: 0),
      modifiedAt: Date(timeIntervalSince1970: 0),
      folder: "Work"
    )

    let tool = Tool.GetNote { _ in
      SingleNoteExecutor(note: noteInput)
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.GetNote.name,
        arguments: ["id": .string("test-note-123")]
      )
    )

    #expect(result.isError == false)

    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: .utf8))
    let notes = try JSONDecoder().decode([Models.Note].self, from: jsonData)

    #expect(notes.count == 1)
    #expect(notes[0].id == "test-note-123")
    #expect(notes[0].title == "Test Note")
    #expect(notes[0].body == "Content")
    #expect(notes[0].folder == "Work")
  }

  @Test
  func executeTrimsWhitespaceAroundIDBeforeScriptGeneration() async throws {
    let sourceStore = ScriptSourceStore()
    let noteInput = NoteDescriptorInput(
      id: "test-note-123",
      title: "Test Note",
      bodyHTML: "<div>Content</div>",
      createdAt: Date(timeIntervalSince1970: 0),
      modifiedAt: Date(timeIntervalSince1970: 0),
      folder: "Work"
    )

    let tool = Tool.GetNote { source in
      sourceStore.set(source)
      return SingleNoteExecutor(note: noteInput)
    }

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.GetNote.name,
        arguments: ["id": .string("  test-note-123  ")]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set noteID to \"test-note-123\""))
    #expect(!source.contains("set noteID to \"  test-note-123  \""))
  }

  @Test
  func executeReturnsMarkdownWhenBodyFormatIsMarkdown() async throws {
    let noteInput = NoteDescriptorInput(
      id: "test-note-123",
      title: "Test Note",
      bodyHTML: "<div><h1>Test Note</h1></div><div><br></div><div><b>Hello</b> <u>World</u></div>",
      createdAt: Date(timeIntervalSince1970: 0),
      modifiedAt: Date(timeIntervalSince1970: 0),
      folder: "Work"
    )

    let tool = Tool.GetNote { _ in
      SingleNoteExecutor(note: noteInput)
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.GetNote.name,
        arguments: [
          "id": .string("test-note-123"),
          "bodyFormat": .string("markdown")
        ]
      )
    )

    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: .utf8))
    let notes = try JSONDecoder().decode([Models.Note].self, from: jsonData)
    #expect(notes[0].body == "**Hello** <u>World</u>")
  }

  @Test
  func executeReturnsRawHTMLWhenBodyFormatIsHTML() async throws {
    let rawBody = "<div><h1>Test Note</h1></div><div><br></div><div><b>Hello</b></div>"
    let noteInput = NoteDescriptorInput(
      id: "test-note-123",
      title: "Test Note",
      bodyHTML: rawBody,
      createdAt: Date(timeIntervalSince1970: 0),
      modifiedAt: Date(timeIntervalSince1970: 0),
      folder: "Work"
    )

    let tool = Tool.GetNote { _ in
      SingleNoteExecutor(note: noteInput)
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.GetNote.name,
        arguments: [
          "id": .string("test-note-123"),
          "bodyFormat": .string("html")
        ]
      )
    )

    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: .utf8))
    let notes = try JSONDecoder().decode([Models.Note].self, from: jsonData)
    #expect(notes[0].body == rawBody)
  }

  @Test
  func executeDoesNotStripWhenLeadingHeadingDoesNotMatchTitle() async throws {
    let noteInput = NoteDescriptorInput(
      id: "test-note-123",
      title: "Test Note",
      bodyHTML: "<div><h1>Different</h1></div><div><br></div><div>Content</div>",
      createdAt: Date(timeIntervalSince1970: 0),
      modifiedAt: Date(timeIntervalSince1970: 0),
      folder: "Work"
    )

    let tool = Tool.GetNote { _ in
      SingleNoteExecutor(note: noteInput)
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.GetNote.name,
        arguments: ["id": .string("test-note-123")]
      )
    )

    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: .utf8))
    let notes = try JSONDecoder().decode([Models.Note].self, from: jsonData)
    #expect(notes[0].body == "Different\n\nContent")
  }

  @Test
  func executeThrowsValidationErrorForMissingID() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(error: GetNoteTestError(message: "should not run"))
    }

    await #expect(throws: Error.GetNote.self) {
      _ = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.GetNote.name))
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyID() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(error: GetNoteTestError(message: "should not run"))
    }

    await #expect(throws: Error.GetNote.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: ["id": .string("   ")]
        )
      )
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDType() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(error: GetNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: ["id": .int(10)]
        )
      )
      Issue.record("Expected validation error for invalid id type")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("expected a string"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidBodyFormatType() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(error: GetNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: [
            "id": .string("test-note-123"),
            "bodyFormat": .bool(true)
          ]
        )
      )
      Issue.record("Expected validation error for invalid bodyFormat type")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("expected a string"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidBodyFormatValue() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(error: GetNoteTestError(message: "should not run"))
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: [
            "id": .string("test-note-123"),
            "bodyFormat": .string("rich")
          ]
        )
      )
      Issue.record("Expected validation error for invalid bodyFormat value")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("expected 'plain', 'markdown', or 'html'"))
    }
  }

  @Test
  func executePropagatesScriptErrors() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(error: GetNoteTestError(message: "Note not found: missing-id"))
    }

    await #expect(throws: GetNoteTestError.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: ["id": .string("missing-id")]
        )
      )
    }
  }

  @Test
  func executeMapsStructuredNoteNotFoundError() async {
    let tool = Tool.GetNote { _ in
      ThrowingGetNoteExecutor(
        error: Error.AppleScript.custom(info: "MCP_NOTE_NOT_FOUND::missing-id")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: ["id": .string("missing-id")]
        )
      )
      Issue.record("Expected note-not-found mapping")
    } catch let error as Error.GetNote {
      #expect(error == .noteNotFound("missing-id"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.GetNote { _ in
      InvalidDescriptorExecutor()
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.GetNote.name,
          arguments: ["id": .string("test-note-123")]
        )
      )
      Issue.record("Expected parsing error for invalid descriptor")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("invalid response"))
    }
  }
}

private struct SingleNoteExecutor: AppleScriptExecuting {
  let note: NoteDescriptorInput

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    DescriptorBuilders.makeSingleNoteDescriptor(note)
  }
}

private struct ThrowingGetNoteExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct InvalidDescriptorExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct GetNoteTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
