import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Batch Get Notes Tool")
struct BatchGetNotesToolTests {
  @Test
  func executeReturnsNotesAndMissingIDsInInputOrderWithDedup() async throws {
    let input = BatchLookupDescriptorInput(
      found: [
        .init(
          id: "note-2",
          title: "Second",
          bodyHTML: "<div><h1>Second</h1></div><div><br></div><div>Body two</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 0),
          folder: "Inbox"
        ),
        .init(
          id: "note-1",
          title: "First",
          bodyHTML: "<div><h1>First</h1></div><div><br></div><div>Body one</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 0),
          folder: "Archive"
        )
      ],
      missing: ["missing-1"]
    )
    let store = BatchLookupStore(inputs: [input])

    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { source in
        store.recordSource(source)
        return StaticBatchLookupExecutor(input: store.takeInput())
      },
      idBatchSize: 10
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchGetNotes.name,
        arguments: [
          "ids": .array([.string("note-2"), .string("note-1"), .string("note-2"), .string("missing-1")])
        ]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload.notes.map(\.id) == ["note-2", "note-1"])
    #expect(payload.notes.map(\.body) == ["Body two", "Body one"])
    #expect(payload.missingIDs == ["missing-1"])
  }

  @Test
  func executeReturnsMarkdownWhenRequested() async throws {
    let input = BatchLookupDescriptorInput(
      found: [
        .init(
          id: "note-1",
          title: "First",
          bodyHTML: "<div><h1>First</h1></div><div><br></div><div><b>Hello</b> <u>World</u></div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 0),
          folder: "Inbox"
        )
      ],
      missing: []
    )

    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        StaticBatchLookupExecutor(input: input)
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchGetNotes.name,
        arguments: [
          "ids": .array([.string("note-1")]),
          "bodyFormat": .string("markdown")
        ]
      )
    )

    let payload = try decodePayload(from: result)
    #expect(payload.notes.count == 1)
    #expect(payload.notes[0].body == "**Hello** <u>World</u>")
  }

  @Test
  func executeReturnsRawHTMLWhenRequested() async throws {
    let rawBody = "<div><h1>First</h1></div><div><br></div><div><b>Hello</b></div>"
    let input = BatchLookupDescriptorInput(
      found: [
        .init(
          id: "note-1",
          title: "First",
          bodyHTML: rawBody,
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 0),
          folder: "Inbox"
        )
      ],
      missing: []
    )

    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        StaticBatchLookupExecutor(input: input)
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchGetNotes.name,
        arguments: [
          "ids": .array([.string("note-1")]),
          "bodyFormat": .string("html")
        ]
      )
    )

    let payload = try decodePayload(from: result)
    #expect(payload.notes.count == 1)
    #expect(payload.notes[0].body == rawBody)
  }

  @Test
  func executeChunksIDsBasedOnBatchSize() async throws {
    let store = BatchLookupStore(inputs: [
      BatchLookupDescriptorInput(
        found: [
          .init(
            id: "note-1",
            title: "First",
            bodyHTML: "<div>One</div>",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            folder: "Inbox"
          ),
          .init(
            id: "note-2",
            title: "Second",
            bodyHTML: "<div>Two</div>",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            folder: "Inbox"
          )
        ],
        missing: []
      ),
      BatchLookupDescriptorInput(
        found: [
          .init(
            id: "note-3",
            title: "Third",
            bodyHTML: "<div>Three</div>",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            folder: "Inbox"
          )
        ],
        missing: []
      )
    ])

    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { source in
        store.recordSource(source)
        return StaticBatchLookupExecutor(input: store.takeInput())
      },
      idBatchSize: 2
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchGetNotes.name,
        arguments: [
          "ids": .array([.string("note-1"), .string("note-2"), .string("note-3")])
        ]
      )
    )

    let payload = try decodePayload(from: result)
    #expect(payload.notes.map(\.id) == ["note-1", "note-2", "note-3"])
    #expect(store.sourceCount() == 2)

    let firstSource = store.source(at: 0)
    let secondSource = store.source(at: 1)
    #expect(firstSource.contains("set requestedIDs to {\"note-1\", \"note-2\"}"))
    #expect(secondSource.contains("set requestedIDs to {\"note-3\"}"))
  }

  @Test
  func executeStopsBeforeSecondChunkWhenTaskIsCancelled() async throws {
    let control = CancellationControl()
    let store = BatchLookupStore(inputs: [
      BatchLookupDescriptorInput(
        found: [
          .init(
            id: "note-1",
            title: "First",
            bodyHTML: "<div>One</div>",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            folder: "Inbox"
          )
        ],
        missing: []
      ),
      BatchLookupDescriptorInput(
        found: [
          .init(
            id: "note-2",
            title: "Second",
            bodyHTML: "<div>Two</div>",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            folder: "Inbox"
          )
        ],
        missing: []
      )
    ])

    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { source in
        store.recordSource(source)
        let index = store.sourceCount()
        if index == 1 {
          return StaticBatchLookupExecutor(
            input: store.takeInput(),
            onRun: {
              control.cancelTask()
            }
          )
        }
        return StaticBatchLookupExecutor(input: store.takeInput())
      },
      idBatchSize: 1
    )

    let task = Task {
      try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchGetNotes.name,
          arguments: [
            "ids": .array([.string("note-1"), .string("note-2")])
          ]
        )
      )
    }
    control.store(task: task)

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    #expect(store.sourceCount() == 1)
  }

  @Test
  func executeThrowsValidationErrorForMissingIDs() async {
    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        ThrowingBatchLookupExecutor(error: BatchGetNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(name: Tool.BatchGetNotes.name)
      )
      Issue.record("Expected missing ids validation error")
    } catch let error as Error.BatchGetNotes {
      #expect(error == .missingIDs)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDsType() async {
    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        ThrowingBatchLookupExecutor(error: BatchGetNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchGetNotes.name,
          arguments: ["ids": .string("note-1")]
        )
      )
      Issue.record("Expected invalid ids type validation error")
    } catch let error as Error.BatchGetNotes {
      #expect(error == .invalidIDsType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDElementType() async {
    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        ThrowingBatchLookupExecutor(error: BatchGetNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchGetNotes.name,
          arguments: [
            "ids": .array([.string("note-1"), .int(2)])
          ]
        )
      )
      Issue.record("Expected invalid id element validation error")
    } catch let error as Error.BatchGetNotes {
      #expect(error == .invalidIDElementType(index: 1))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyIDElement() async {
    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        ThrowingBatchLookupExecutor(error: BatchGetNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchGetNotes.name,
          arguments: [
            "ids": .array([.string("note-1"), .string("   ")])
          ]
        )
      )
      Issue.record("Expected empty id element validation error")
    } catch let error as Error.BatchGetNotes {
      #expect(error == .emptyID(index: 1))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.BatchGetNotes(
      appleScriptFactory: { _ in
        InvalidBatchLookupExecutor()
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchGetNotes.name,
          arguments: [
            "ids": .array([.string("note-1")])
          ]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.BatchGetNotes {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.BatchGetNotesResult {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: String.Encoding.utf8))
    return try JSONDecoder().decode(Models.BatchGetNotesResult.self, from: data)
  }
}

private struct BatchLookupDescriptorInput: Sendable {
  let found: [NoteDescriptorInput]
  let missing: [String]
}

private struct StaticBatchLookupExecutor: AppleScriptExecuting {
  let input: BatchLookupDescriptorInput
  let onRun: (@Sendable () -> Void)?

  init(input: BatchLookupDescriptorInput, onRun: (@Sendable () -> Void)? = nil) {
    self.input = input
    self.onRun = onRun
  }

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    onRun?()
    let foundRows = NSAppleEventDescriptor.list()
    for (index, note) in input.found.enumerated() {
      foundRows.insert(DescriptorBuilders.makeSingleNoteDescriptor(note), at: index + 1)
    }

    let missingRows = NSAppleEventDescriptor.list()
    for (index, missing) in input.missing.enumerated() {
      missingRows.insert(NSAppleEventDescriptor(string: missing), at: index + 1)
    }

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(foundRows, at: 1)
    descriptor.insert(missingRows, at: 2)
    return descriptor
  }
}

private struct InvalidBatchLookupExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct ThrowingBatchLookupExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct BatchGetNotesTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}

private final class BatchLookupStore: @unchecked Sendable {
  private let lock = NSLock()
  private var sources: [String] = []
  private var inputs: [BatchLookupDescriptorInput]
  private var cursor = 0

  init(inputs: [BatchLookupDescriptorInput]) {
    self.inputs = inputs
  }

  func recordSource(_ source: String) {
    lock.lock()
    sources.append(source)
    lock.unlock()
  }

  func sourceCount() -> Int {
    lock.lock()
    let value = sources.count
    lock.unlock()
    return value
  }

  func source(at index: Int) -> String {
    lock.lock()
    let value = sources[index]
    lock.unlock()
    return value
  }

  func takeInput() -> BatchLookupDescriptorInput {
    lock.lock()
    let value = inputs[cursor]
    cursor += 1
    lock.unlock()
    return value
  }
}

private final class CancellationControl: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<CallTool.Result, Swift.Error>?

  func store(task: Task<CallTool.Result, Swift.Error>) {
    lock.lock()
    self.task = task
    lock.unlock()
  }

  func cancelTask() {
    lock.lock()
    let currentTask = task
    lock.unlock()
    currentTask?.cancel()
  }
}
