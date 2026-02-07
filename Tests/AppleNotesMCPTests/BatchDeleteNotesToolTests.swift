import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("Batch Delete Notes Tool")
struct BatchDeleteNotesToolTests {
  @Test
  func executeReturnsDeletedMissingAndFailedInInputOrderWithDedup() async throws {
    let input = BatchDeleteDescriptorInput(
      deletedIDs: ["note-2", "note-1"],
      missingIDs: ["missing-1"],
      failedRows: [.init(id: "locked-1", reason: "Deletion denied")]
    )
    let store = BatchDeleteStore(inputs: [input])

    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { source in
        store.recordSource(source)
        return StaticBatchDeleteExecutor(input: store.takeInput())
      },
      idBatchSize: 10
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchDeleteNotes.name,
        arguments: [
          "ids": .array([
            .string("note-2"),
            .string("note-1"),
            .string("note-2"),
            .string("missing-1"),
            .string("locked-1")
          ])
        ]
      )
    )

    #expect(result.isError == false)
    let payload = try decodePayload(from: result)
    #expect(payload.deletedIDs == ["note-2", "note-1"])
    #expect(payload.missingIDs == ["missing-1"])
    #expect(payload.failed == [.init(id: "locked-1", reason: "Deletion denied")])
  }

  @Test
  func executeReturnsResolvedDeletedIDsFromScript() async throws {
    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { _ in
        StaticBatchDeleteExecutor(
          input: .init(
            deletedIDs: ["resolved-id-1"],
            missingIDs: [],
            failedRows: []
          )
        )
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchDeleteNotes.name,
        arguments: [
          "ids": .array([.string("input-id-1")])
        ]
      )
    )

    let payload = try decodePayload(from: result)
    #expect(payload.deletedIDs == ["resolved-id-1"])
  }

  @Test
  func executeChunksIDsBasedOnBatchSize() async throws {
    let store = BatchDeleteStore(inputs: [
      .init(
        deletedIDs: ["note-1", "note-2"],
        missingIDs: [],
        failedRows: []
      ),
      .init(
        deletedIDs: ["note-3"],
        missingIDs: [],
        failedRows: []
      )
    ])

    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { source in
        store.recordSource(source)
        return StaticBatchDeleteExecutor(input: store.takeInput())
      },
      idBatchSize: 2
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.BatchDeleteNotes.name,
        arguments: [
          "ids": .array([.string("note-1"), .string("note-2"), .string("note-3")])
        ]
      )
    )

    let payload = try decodePayload(from: result)
    #expect(payload.deletedIDs == ["note-1", "note-2", "note-3"])
    #expect(store.sourceCount() == 2)

    let firstSource = store.source(at: 0)
    let secondSource = store.source(at: 1)
    #expect(firstSource.contains("set requestedIDs to {\"note-1\", \"note-2\"}"))
    #expect(secondSource.contains("set requestedIDs to {\"note-3\"}"))
  }

  @Test
  func executeStopsBeforeSecondChunkWhenTaskIsCancelled() async throws {
    let control = BatchDeleteCancellationControl()
    let store = BatchDeleteStore(inputs: [
      .init(
        deletedIDs: ["note-1"],
        missingIDs: [],
        failedRows: []
      ),
      .init(
        deletedIDs: ["note-2"],
        missingIDs: [],
        failedRows: []
      )
    ])

    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { source in
        store.recordSource(source)
        let index = store.sourceCount()
        if index == 1 {
          return StaticBatchDeleteExecutor(
            input: store.takeInput(),
            onRun: {
              control.cancelTask()
            }
          )
        }
        return StaticBatchDeleteExecutor(input: store.takeInput())
      },
      idBatchSize: 1
    )

    let task = Task {
      try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchDeleteNotes.name,
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
    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { _ in
        ThrowingBatchDeleteExecutor(error: BatchDeleteNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.BatchDeleteNotes.name))
      Issue.record("Expected missing ids validation error")
    } catch let error as Error.BatchDeleteNotes {
      #expect(error == .missingIDs)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDsType() async {
    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { _ in
        ThrowingBatchDeleteExecutor(error: BatchDeleteNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchDeleteNotes.name,
          arguments: ["ids": .string("note-1")]
        )
      )
      Issue.record("Expected invalid ids type validation error")
    } catch let error as Error.BatchDeleteNotes {
      #expect(error == .invalidIDsType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIDElementType() async {
    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { _ in
        ThrowingBatchDeleteExecutor(error: BatchDeleteNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchDeleteNotes.name,
          arguments: [
            "ids": .array([.string("note-1"), .int(2)])
          ]
        )
      )
      Issue.record("Expected invalid id element validation error")
    } catch let error as Error.BatchDeleteNotes {
      #expect(error == .invalidIDElementType(index: 1))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyIDElement() async {
    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { _ in
        ThrowingBatchDeleteExecutor(error: BatchDeleteNotesTestError(message: "should not run"))
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchDeleteNotes.name,
          arguments: [
            "ids": .array([.string("note-1"), .string("   ")])
          ]
        )
      )
      Issue.record("Expected empty id element validation error")
    } catch let error as Error.BatchDeleteNotes {
      #expect(error == .emptyID(index: 1))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsErrorForInvalidScriptDescriptor() async {
    let tool = Tool.BatchDeleteNotes(
      appleScriptFactory: { _ in
        InvalidBatchDeleteExecutor()
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.BatchDeleteNotes.name,
          arguments: ["ids": .array([.string("note-1")])]
        )
      )
      Issue.record("Expected invalid script response error")
    } catch let error as Error.BatchDeleteNotes {
      #expect(error == .invalidScriptResponse)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.BatchDeleteNotesResult {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: String.Encoding.utf8))
    return try JSONDecoder().decode(Models.BatchDeleteNotesResult.self, from: data)
  }
}

private struct BatchDeleteDescriptorInput: Sendable {
  let deletedIDs: [String]
  let missingIDs: [String]
  let failedRows: [Models.BatchDeleteFailure]
}

private struct StaticBatchDeleteExecutor: AppleScriptExecuting {
  let input: BatchDeleteDescriptorInput
  let onRun: (@Sendable () -> Void)?

  init(input: BatchDeleteDescriptorInput, onRun: (@Sendable () -> Void)? = nil) {
    self.input = input
    self.onRun = onRun
  }

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    onRun?()

    let deletedRows = NSAppleEventDescriptor.list()
    for (index, deletedID) in input.deletedIDs.enumerated() {
      deletedRows.insert(NSAppleEventDescriptor(string: deletedID), at: index + 1)
    }

    let missingRows = NSAppleEventDescriptor.list()
    for (index, missingID) in input.missingIDs.enumerated() {
      missingRows.insert(NSAppleEventDescriptor(string: missingID), at: index + 1)
    }

    let failedRows = NSAppleEventDescriptor.list()
    for (index, failed) in input.failedRows.enumerated() {
      let row = NSAppleEventDescriptor.list()
      row.insert(NSAppleEventDescriptor(string: failed.id), at: 1)
      row.insert(NSAppleEventDescriptor(string: failed.reason), at: 2)
      failedRows.insert(row, at: index + 1)
    }

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(deletedRows, at: 1)
    descriptor.insert(missingRows, at: 2)
    descriptor.insert(failedRows, at: 3)
    return descriptor
  }
}

private struct InvalidBatchDeleteExecutor: AppleScriptExecuting {
  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.list()
  }
}

private struct ThrowingBatchDeleteExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private struct BatchDeleteNotesTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}

private final class BatchDeleteStore: @unchecked Sendable {
  private let lock = NSLock()
  private var sources: [String] = []
  private var inputs: [BatchDeleteDescriptorInput]
  private var cursor = 0

  init(inputs: [BatchDeleteDescriptorInput]) {
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

  func takeInput() -> BatchDeleteDescriptorInput {
    lock.lock()
    let value = inputs[cursor]
    cursor += 1
    lock.unlock()
    return value
  }
}

private final class BatchDeleteCancellationControl: @unchecked Sendable {
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
