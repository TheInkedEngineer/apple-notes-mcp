import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Create Note Tool")
struct CreateNoteToolTests {
  @Test
  func executeThrowsValidationErrorForMissingTitle() async {
    let tool = makeTool()

    await #expect(throws: Error.CreateNote.self) {
      _ = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.CreateNote.name))
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyTitle() async {
    let tool = makeTool()

    await #expect(throws: Error.CreateNote.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: ["title": .string("   ")]
        )
      )
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidBodyType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "body": .int(1)
          ]
        )
      )
      Issue.record("Expected invalid body type error")
    } catch let error as Error.CreateNote {
      #expect(error == .invalidBodyType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidBodyFormatType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "bodyFormat": .int(1)
          ]
        )
      )
      Issue.record("Expected invalid bodyFormat type error")
    } catch let error as Error.CreateNote {
      #expect(error == .invalidBodyFormatType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidBodyFormatValue() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "bodyFormat": .string("rich")
          ]
        )
      )
      Issue.record("Expected invalid bodyFormat value error")
    } catch let error as Error.CreateNote {
      #expect(error == .invalidBodyFormatValue("rich"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidFolderType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .int(1)
          ]
        )
      )
      Issue.record("Expected invalid folder type error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidFolderType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyFolder() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .string("   ")
          ]
        )
      )
      Issue.record("Expected empty folder error")
    } catch let error as Error.FolderResolution {
      #expect(error == .emptyFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidFolderPathWithMultipleSlashes() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .string("Work//Sub")
          ]
        )
      )
      Issue.record("Expected invalid folder path format error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidFolderPathFormat("Work//Sub"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidAccountType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "account": .int(1)
          ]
        )
      )
      Issue.record("Expected invalid account type error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidAccountType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyAccount() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "account": .string("   ")
          ]
        )
      )
      Issue.record("Expected empty account error")
    } catch let error as Error.FolderResolution {
      #expect(error == .emptyAccount)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidFolderPathWithEmptyAccountSegment() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .string("/Work")
          ]
        )
      )
      Issue.record("Expected invalid folder path format error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidFolderPathFormat("/Work"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidFolderPathWithEmptyFolderSegment() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .string("iCloud/")
          ]
        )
      )
      Issue.record("Expected invalid folder path format error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidFolderPathFormat("iCloud/"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeTrimsWhitespaceFromTitleAndFolderPath() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("  Hello  "),
          "account": .string("  iCloud  "),
          "folder": .string("  Work  ")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set n to make new note with properties {name:\"\", body:bodyValue}"))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set fullPath to \"Work\""))
    #expect(source.contains("set folderLeaf to \"Work\""))
    #expect(source.contains("set theFolderName to folderLeaf"))
  }

  @Test
  func executeNormalizesNewlinesAndEscapesHTMLInBody() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Body Test"),
          "body": .string("Line 1\r\nLine 2\rLine 3\n&<>")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set titleValue to \"Body Test\""))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set bodyValue to \"<div><h1>Body Test</h1></div><div><br></div>"))
    #expect(source.contains("Line 1<br>Line 2<br>Line 3<br>&amp;&lt;&gt;"))
    #expect(source.contains("set theFolderName to name of (container of n) as string"))
  }

  @Test
  func executeBodyFormatHTMLPassesRichBodyAsProvided() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Body Test"),
          "bodyFormat": .string("html"),
          "body": .string("<div><b>Hello</b></div>")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set titleValue to \"Body Test\""))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set bodyValue to \"<div><h1>Body Test</h1></div><div><br></div><div><b>Hello</b></div>\""))
  }

  @Test
  func executeBodyFormatMarkdownConvertsMarkdownToRichHTML() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Body Test"),
          "bodyFormat": .string("markdown"),
          "body": .string("## Heading\n\nHello **World**\n- one\n- two")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set titleValue to \"Body Test\""))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set bodyValue to \"<div><h1>Body Test</h1></div><div><br></div>"))
    #expect(source.contains("<div><h2>Heading</h2></div>"))
    #expect(source.contains("<div>Hello <b>World</b></div>"))
    #expect(source.contains("<ul><li>one</li><li>two</li></ul>"))
  }

  @Test
  func executeWithEmptyBodyStoresHeadingOnly() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Q1-updated"),
          "body": .string("")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set titleValue to \"Q1-updated\""))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set bodyValue to \"<div><h1>Q1-updated</h1></div>\""))
  }

  @Test
  func executeAccountOnlyBuildsAccountScopedScript() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Title"),
          "account": .string("iCloud")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("tell targetAccount"))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set theFolderName to name of (container of n) as string"))
  }

  @Test
  func executeSearchAllFolderScriptReturnsKnownFolderName() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Title"),
          "folder": .string("Work")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set fullPath to \"Work\""))
    #expect(source.contains("set folderLeaf to \"Work\""))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("set theFolderName to folderLeaf"))
    #expect(!source.contains("set theFolderName to name of (container of n) as string"))
  }

  @Test
  func executeBuildsNestedFolderPathSegmentsForSpecificAccount() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Nested"),
          "account": .string("iCloud"),
          "folder": .string("Jokes/IT/Deep")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set pathSegments to {\"Jokes\", \"IT\", \"Deep\"}"))
    #expect(source.contains("set fullPath to \"Jokes/IT/Deep\""))
    #expect(source.contains("set folderLeaf to \"Deep\""))
  }

  @Test
  func executeSupportsUnicodeInFolderPath() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Title"),
          "account": .string("iCloud"),
          "folder": .string("日本語")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set folderLeaf to \"日本語\""))
  }

  @Test
  func executeSupportsUnicodeInAccountName() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Title"),
          "account": .string("仕事"),
          "folder": .string("Work")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set accountName to \"仕事\""))
  }

  @Test
  func executeEscapesQuotesAndBackslashesInInterpolatedValues() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("A \"quoted\" title"),
          "body": .string("Path: C:\\\\work"),
          "account": .string("iCloud"),
          "folder": .string("Work \"A\"")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("set n to make new note with properties {name:\"\", body:bodyValue}"))
    #expect(source.contains("set name of n to titleValue"))
    #expect(source.contains("Path: C:\\\\\\\\work"))
    #expect(source.contains("set bodyValue to \"<div><h1>A &quot;quoted&quot; title</h1></div><div><br></div>"))
    #expect(source.contains(#"set folderLeaf to "Work \"A\"""#))
  }

  @Test
  func executeEscapesTitleWhenInjectedIntoHeading() async throws {
    let capturedSource = ScriptSourceStore()
    let tool = makeTool(sourceStore: capturedSource)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("R&D <Q1> \"Go\""),
          "body": .string("Body")
        ]
      )
    )

    let source = capturedSource.value()
    #expect(source.contains("<div><h1>R&amp;D &lt;Q1&gt; &quot;Go&quot;</h1></div><div><br></div>"))
  }

  @Test
  func executeMapsStructuredAccountNotFoundError() async {
    let tool = Tool.CreateNote { _ in
      ThrowingCreateNoteAppleScriptExecutor(
        error: Error.AppleScript.custom(info: "MCP_ACCOUNT_NOT_FOUND::iCloud")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "account": .string("iCloud"),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected mapped account not found error")
    } catch let error as Error.FolderResolution {
      #expect(error == .accountNotFound("iCloud"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredFolderNotFoundError() async {
    let tool = Tool.CreateNote { _ in
      ThrowingCreateNoteAppleScriptExecutor(
        error: Error.AppleScript.custom(info: "MCP_FOLDER_NOT_FOUND::IT::Jokes/IT/Deep")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected mapped folder not found error")
    } catch let error as Error.FolderResolution {
      #expect(error == .folderNotFound(segment: "IT", path: "Jokes/IT/Deep"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredAmbiguousFolderError() async {
    let tool = Tool.CreateNote { _ in
      ThrowingCreateNoteAppleScriptExecutor(
        error: Error.AppleScript.custom(info: "MCP_FOLDER_AMBIGUOUS::Jokes/IT::iCloud||On My Mac")
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: [
            "title": .string("Title"),
            "folder": .string("Jokes/IT")
          ]
        )
      )
      Issue.record("Expected mapped ambiguous folder error")
    } catch let error as Error.FolderResolution {
      #expect(error == .ambiguousFolder(path: "Jokes/IT", accounts: ["iCloud", "On My Mac"]))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executePropagatesUnknownScriptErrors() async {
    let tool = Tool.CreateNote { _ in
      ThrowingCreateNoteAppleScriptExecutor(
        error: Error.AppleScript.custom(info: "unstructured failure")
      )
    }

    await #expect(throws: Error.AppleScript.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: ["title": .string("Title")]
        )
      )
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let note = sampleCreatedNote
    let tool = Tool.CreateNote { _ in
      StaticCreateNoteAppleScriptExecutor(
        note: note,
        descriptorMode: .listItem
      )
    }

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.CreateNote.name,
          arguments: ["title": .string("Title")]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.CreateNote {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeReturnsCreatedNotePayload() async throws {
    let note = sampleCreatedNote
    let tool = Tool.CreateNote { _ in
      StaticCreateNoteAppleScriptExecutor(
        note: note,
        descriptorMode: .singleNote
      )
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("  Standup Ideas  "),
          "body": .string("Line 1\nLine 2")
        ]
      )
    )

    #expect(result.isError == false)
    let notes = try decodeNotes(from: result)
    #expect(notes.count == 1)
    #expect(notes[0].id == "note-created")
    #expect(notes[0].title == "Standup Ideas")
    #expect(notes[0].body == "Line 1\nLine 2")
    #expect(notes[0].folder == "Work")
  }

  @Test
  func executeStripsLeadingTitleHeadingFromReturnedBody() async throws {
    let note = NoteDescriptorInput(
      id: "note-created",
      title: "Standup Ideas",
      bodyHTML: "<div><h1>Standup Ideas</h1></div><div><br></div><div>Line 1</div><div>Line 2</div>",
      createdAt: Date(timeIntervalSince1970: 100),
      modifiedAt: Date(timeIntervalSince1970: 200),
      folder: "Work"
    )
    let tool = Tool.CreateNote { _ in
      StaticCreateNoteAppleScriptExecutor(
        note: note,
        descriptorMode: .singleNote
      )
    }

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.CreateNote.name,
        arguments: [
          "title": .string("Standup Ideas"),
          "body": .string("Line 1\nLine 2")
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes[0].body == "Line 1\nLine 2")
  }

  private func makeTool(
    sourceStore: ScriptSourceStore = ScriptSourceStore(),
    note: NoteDescriptorInput? = nil,
    descriptorMode: CreateNoteDescriptorMode = .singleNote
  ) -> AppleNotesMCP.Tool.CreateNote {
    let resolvedNote = note ?? sampleCreatedNote
    return Tool.CreateNote { source in
      sourceStore.set(source)
      return StaticCreateNoteAppleScriptExecutor(
        note: resolvedNote,
        descriptorMode: descriptorMode
      )
    }
  }

  private func decodeNotes(from result: CallTool.Result) throws -> [Models.Note] {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode([Models.Note].self, from: jsonData)
  }

  private var sampleCreatedNote: NoteDescriptorInput {
    NoteDescriptorInput(
      id: "note-created",
      title: "Standup Ideas",
      bodyHTML: "Line 1<br>Line 2",
      createdAt: Date(timeIntervalSince1970: 100),
      modifiedAt: Date(timeIntervalSince1970: 200),
      folder: "Work"
    )
  }
}

private struct StaticCreateNoteAppleScriptExecutor: AppleScriptExecuting {
  let note: NoteDescriptorInput
  let descriptorMode: CreateNoteDescriptorMode

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    switch descriptorMode {
    case .singleNote:
      return DescriptorBuilders.makeSingleNoteDescriptor(note)
    case .listItem:
      return DescriptorBuilders.makeListItemDescriptor(
        NoteMetadataDescriptorInput(
          id: note.id,
          title: note.title,
          createdAt: note.createdAt,
          modifiedAt: note.modifiedAt,
          folder: note.folder
        )
      )
    }
  }
}

private struct ThrowingCreateNoteAppleScriptExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private enum CreateNoteDescriptorMode: Sendable {
  case singleNote
  case listItem
}
