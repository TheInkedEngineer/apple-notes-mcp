import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Update Note Tool")
struct UpdateNoteToolTests {
  @Test
  func executeThrowsValidationErrorForMissingID() async {
    let tool = makeTool(items: [])

    await #expect(throws: Error.UpdateNote.self) {
      _ = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.UpdateNote.name))
    }
  }

  @Test
  func executeThrowsValidationErrorWhenNoChangesProvided() async {
    let tool = makeTool(items: [])

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.UpdateNote.name,
          arguments: ["id": .string("note-1")]
        )
      )
      Issue.record("Expected no changes validation error")
    } catch let error as Error.UpdateNote {
      #expect(error == .noChangesRequested)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorWhenBodyModeProvidedWithoutBody() async {
    let tool = makeTool(items: [])

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.UpdateNote.name,
          arguments: [
            "id": .string("note-1"),
            "title": .string("Updated"),
            "bodyMode": .string("append")
          ]
        )
      )
      Issue.record("Expected bodyMode requires body validation error")
    } catch let error as Error.UpdateNote {
      #expect(error == .bodyModeRequiresBody)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeTitleOnlyUpdatesNameAndResyncsHeading() async throws {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Old Title",
          bodyHTML: "<div><h1>Old Title</h1></div><div><br></div><div>Existing</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "New Title",
          bodyHTML: "<div><h1>New Title</h1></div><div><br></div><div>Existing</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 2),
          folder: "Work"
        )
      ))
    ])
    let tool = makeTool(queue: queue)

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.UpdateNote.name,
        arguments: [
          "id": .string("note-1"),
          "title": .string("New Title")
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.count == 1)
    #expect(notes[0].title == "New Title")
    #expect(notes[0].body == "Existing")

    let sources = queue.sources()
    #expect(sources.count == 2)
    #expect(sources[1].contains("set newTitleValue to \"New Title\""))
    #expect(sources[1].contains("set name of n to newTitleValue"))
    #expect(sources[1].contains("set newBodyValue to \"<div><h1>New Title</h1></div><div><br></div><div>Existing</div>\""))
    let bodySetIndex = try #require(sources[1].range(of: "set body of n to newBodyValue")?.lowerBound)
    let nameSetIndex = try #require(sources[1].range(of: "set name of n to newTitleValue")?.lowerBound)
    #expect(bodySetIndex < nameSetIndex)
  }

  @Test
  func executeBodyReplaceUsesPreparedBody() async throws {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div><div>Old</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div>Line 1<br>Line 2",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 2),
          folder: "Work"
        )
      ))
    ])
    let tool = makeTool(queue: queue)

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.UpdateNote.name,
        arguments: [
          "id": .string("note-1"),
          "body": .string("Line 1\nLine 2")
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes[0].body == "Line 1\nLine 2")
  }

  @Test
  func executeBodyAppendCombinesExistingAndNewBody() async throws {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div><div>Existing</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div><div>Existing</div><div><br></div>New",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 2),
          folder: "Work"
        )
      ))
    ])
    let tool = makeTool(queue: queue)

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.UpdateNote.name,
        arguments: [
          "id": .string("note-1"),
          "body": .string("New"),
          "bodyMode": .string("append")
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes[0].body == "Existing\n\nNew")
  }

  @Test
  func executeBodyPrependCombinesExistingAndNewBody() async throws {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div><div>Existing</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div>New<div><br></div><div>Existing</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 2),
          folder: "Work"
        )
      ))
    ])
    let tool = makeTool(queue: queue)

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.UpdateNote.name,
        arguments: [
          "id": .string("note-1"),
          "body": .string("New"),
          "bodyMode": .string("prepend")
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes[0].body == "New\n\nExisting")
  }

  @Test
  func executeBodyMarkdownUsesMarkdownPreparation() async throws {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div><div>Old</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: "<div><h1>Title</h1></div><div><br></div><div><h2>Heading</h2></div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 2),
          folder: "Work"
        )
      ))
    ])
    let tool = makeTool(queue: queue)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.UpdateNote.name,
        arguments: [
          "id": .string("note-1"),
          "body": .string("## Heading"),
          "bodyFormat": .string("markdown")
        ]
      )
    )

    let writeSource = queue.sources()[1]
    #expect(writeSource.contains("<div><h2>Heading</h2></div>"))
  }

  @Test
  func executeReturnsRawHTMLWhenOutputBodyFormatIsHTML() async throws {
    let rawBody = "<div><h1>Title</h1></div><div><br></div><div><b>Rich</b></div>"
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: rawBody,
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Title",
          bodyHTML: rawBody,
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 2),
          folder: "Work"
        )
      ))
    ])
    let tool = makeTool(queue: queue)

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.UpdateNote.name,
        arguments: [
          "id": .string("note-1"),
          "title": .string("Title"),
          "outputBodyFormat": .string("html")
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes[0].body == rawBody)
  }

  @Test
  func executeMapsStructuredNoteNotFoundFromReadScript() async {
    let queue = ScriptQueue(items: [
      .error(Error.AppleScript.custom(info: "MCP_NOTE_NOT_FOUND::missing-id"))
    ])
    let tool = makeTool(queue: queue)

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.UpdateNote.name,
          arguments: [
            "id": .string("missing-id"),
            "title": .string("New")
          ]
        )
      )
      Issue.record("Expected note not found error")
    } catch let error as Error.UpdateNote {
      #expect(error == .noteNotFound("missing-id"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredNoteNotFoundFromWriteScript() async {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Old",
          bodyHTML: "<div><h1>Old</h1></div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .error(Error.AppleScript.custom(info: "MCP_NOTE_NOT_FOUND::note-1"))
    ])
    let tool = makeTool(queue: queue)

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.UpdateNote.name,
          arguments: [
            "id": .string("note-1"),
            "title": .string("New")
          ]
        )
      )
      Issue.record("Expected note not found error")
    } catch let error as Error.UpdateNote {
      #expect(error == .noteNotFound("note-1"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsInvalidScriptResponseWhenWriteDescriptorIsMalformed() async {
    let queue = ScriptQueue(items: [
      .descriptor(DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "Old",
          bodyHTML: "<div><h1>Old</h1></div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 1),
          folder: "Work"
        )
      )),
      .descriptor(NSAppleEventDescriptor.list())
    ])
    let tool = makeTool(queue: queue)

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.UpdateNote.name,
          arguments: [
            "id": .string("note-1"),
            "title": .string("New")
          ]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.UpdateNote {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func makeTool(items: [ScriptQueue.Item]) -> AppleNotesMCP.Tool.UpdateNote {
    makeTool(queue: ScriptQueue(items: items))
  }

  private func makeTool(queue: ScriptQueue) -> AppleNotesMCP.Tool.UpdateNote {
    AppleNotesMCP.Tool.UpdateNote { source in
      queue.record(source: source)
      return QueueExecutor(queue: queue)
    }
  }

  private func decodeNotes(from result: CallTool.Result) throws -> [Models.Note] {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: String.Encoding.utf8))
    return try JSONDecoder().decode([Models.Note].self, from: jsonData)
  }
}

private struct QueueExecutor: AppleScriptExecuting {
  let queue: ScriptQueue

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    try queue.nextDescriptor()
  }
}

private final class ScriptQueue: @unchecked Sendable {
  enum Item {
    case descriptor(NSAppleEventDescriptor)
    case error(any Swift.Error & Sendable)
  }

  private let lock = NSLock()
  private var items: [Item]
  private var recordedSources: [String] = []

  init(items: [Item]) {
    self.items = items
  }

  func record(source: String) {
    lock.lock()
    recordedSources.append(source)
    lock.unlock()
  }

  func sources() -> [String] {
    lock.lock()
    let copy = recordedSources
    lock.unlock()
    return copy
  }

  func nextDescriptor() throws -> NSAppleEventDescriptor {
    lock.lock()
    defer { lock.unlock() }

    guard !items.isEmpty else {
      throw Error.AppleScript.custom(info: "No queued script result available.")
    }

    let next = items.removeFirst()
    switch next {
    case let .descriptor(descriptor):
      return descriptor
    case let .error(error):
      throw error
    }
  }
}
