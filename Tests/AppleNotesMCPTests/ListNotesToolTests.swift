import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@MainActor
@Suite("List Notes Tool")
struct ListNotesToolTests {
  @Test
  func executeReturnsAllNotesInNativeOrderByDefault() async throws {
    let tool = makeTool()

    let result = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.ListNotes.name))
    #expect(result.isError == false)

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1", "note-2", "note-3"])
    #expect(notes.allSatisfy { $0.body == nil })
  }

  @Test
  func executeResolvesEmptyMetadataTitlesFromBodyHeadings() async throws {
    let noteWithEmptyTitle = [
      NoteMetadataDescriptorInput(
        id: "note-empty",
        title: "",
        createdAt: Date(timeIntervalSince1970: 100),
        modifiedAt: Date(timeIntervalSince1970: 100),
        folder: "Inbox"
      )
    ]

    let tool = Tool.ListNotes(
      appleScriptFactory: { _ in
        StaticAppleScriptExecutor(notes: noteWithEmptyTitle)
      },
      bodyLookup: { _ in
        [
          "note-empty": "<div><h1>Recovered Title</h1></div><div><br></div><div>Body</div>"
        ]
      }
    )

    let result = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.ListNotes.name))
    let notes = try decodeNotes(from: result)
    #expect(notes.count == 1)
    #expect(notes[0].title == "Recovered Title")
  }

  @Test
  func executeIncludeBodyTrueWithoutSearchFetchesBodiesForSelectedNotes() async throws {
    let recorder = BodyLookupRecorder()
    let bodiesByID = defaultBodiesByID
    let tool = makeTool(
      bodyLookup: { noteIDs in
        await recorder.record(ids: noteIDs)
        var result: [String: String] = [:]
        for id in noteIDs {
          if let body = bodiesByID[id] {
            result[id] = body
          }
        }
        return result
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "includeBody": .bool(true),
          "limit": .int(2)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1", "note-2"])
    #expect(notes.map { $0.body } == ["Kickoff agenda", "Contains callback example"])

    let batches = await recorder.recordedBatches()
    #expect(batches.count == 1)
    #expect(batches[0] == ["note-1", "note-2"])
  }

  @Test
  func executeIncludeBodyTrueKeepsNotesWhenIndividualBodiesAreUnavailable() async throws {
    let recorder = BodyLookupRecorder()
    let tool = makeTool(
      bodyLookup: { noteIDs in
        await recorder.record(ids: noteIDs)
        // Simulate partial lookup failure by omitting note-2.
        return ["note-1": "Kickoff agenda"]
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "includeBody": .bool(true),
          "limit": .int(2)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1", "note-2"])
    #expect(notes[0].body == "Kickoff agenda")
    #expect(notes[1].body == nil)

    let batches = await recorder.recordedBatches()
    #expect(batches.count == 1)
    #expect(batches[0] == ["note-1", "note-2"])
  }

  @Test
  func executeFiltersByTitleWhenSearchTextProvidedWithoutSearchIn() async throws {
    let tool = makeTool()

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["searchText": .string("standup")]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1"])
  }

  @Test
  func executeSearchInBodyHonorsOrderingAndLimit() async throws {
    let tool = makeTool()

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("example"),
          "searchIn": .string("body"),
          "orderBy": .string("modified"),
          "orderDirection": .string("recent"),
          "limit": .int(2)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
  }

  @Test
  func executeSearchInBodyAppliesOffsetOnMatchedResults() async throws {
    let tool = makeTool()

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("example"),
          "searchIn": .string("body"),
          "orderBy": .string("modified"),
          "orderDirection": .string("recent"),
          "offset": .int(1),
          "limit": .int(1)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-3"])
  }

  @Test
  func executeBodySearchDoesNotMatchInjectedTitleHeadingOnly() async throws {
    let tool = makeTool(
      bodyLookup: { noteIDs in
        var result: [String: String] = [:]
        for id in noteIDs {
          if id == "note-1" {
            result[id] = "<div><h1>Standup Recap</h1></div><div><br></div><div>No keyword here</div>"
          } else if id == "note-2" {
            result[id] = "<div><h1>Quarterly Plan</h1></div><div><br></div><div>Nothing else</div>"
          } else if id == "note-3" {
            result[id] = "<div><h1>Comedy Ideas</h1></div><div><br></div><div>No keyword</div>"
          }
        }
        return result
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("Standup Recap"),
          "searchIn": .string("body"),
          "limit": .int(10)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.isEmpty)
  }

  @Test
  func executeSearchInBodyWithIncludeBodyReusesFetchedBodies() async throws {
    let recorder = BodyLookupRecorder()
    let bodiesByID = defaultBodiesByID
    let tool = makeTool(
      bodyBatchSize: 2,
      bodyLookup: { noteIDs in
        await recorder.record(ids: noteIDs)
        var result: [String: String] = [:]
        for id in noteIDs {
          if let body = bodiesByID[id] {
            result[id] = body
          }
        }
        return result
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("example"),
          "searchIn": .string("body"),
          "includeBody": .bool(true),
          "orderBy": .string("modified"),
          "orderDirection": .string("recent"),
          "limit": .int(2)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
    #expect(notes.map { $0.body } == ["Contains callback example", "Standup open mic example"])

    let batches = await recorder.recordedBatches()
    #expect(batches.count == 1)
    #expect(batches[0] == ["note-2", "note-3"])
  }

  @Test
  func executeSearchInAllSkipsBodyLookupForTitleMatches() async throws {
    let recorder = BodyLookupRecorder()
    let tool = makeTool(
      bodyBatchSize: 2,
      bodyLookup: { noteIDs in
        await recorder.record(ids: noteIDs)
        return [
          "note-2": "planning content",
          "note-3": "open mic notes"
        ]
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("standup"),
          "searchIn": .string("all"),
          "orderBy": .string("modified"),
          "orderDirection": .string("oldest"),
          "limit": .int(1)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1"])

    let batches = await recorder.recordedBatches()
    #expect(batches.isEmpty)
  }

  @Test
  func executeSearchInAllWithIncludeBodyFillsTitleMatchesAfterSelection() async throws {
    let recorder = BodyLookupRecorder()
    let bodiesByID = defaultBodiesByID
    let tool = makeTool(
      bodyBatchSize: 2,
      bodyLookup: { noteIDs in
        await recorder.record(ids: noteIDs)
        var result: [String: String] = [:]
        for id in noteIDs {
          if let body = bodiesByID[id] {
            result[id] = body
          }
        }
        return result
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("standup"),
          "searchIn": .string("all"),
          "includeBody": .bool(true),
          "orderBy": .string("created"),
          "orderDirection": .string("oldest"),
          "limit": .int(2)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1", "note-3"])
    #expect(notes.map { $0.body } == ["Kickoff agenda", "Standup open mic example"])

    let batches = await recorder.recordedBatches()
    #expect(batches.count == 2)
    #expect(batches[0] == ["note-2", "note-3"])
    #expect(batches[1] == ["note-1"])
  }

  @Test
  func executeUsesBodyLookupBatchesWhenSearchingBody() async throws {
    let recorder = BodyLookupRecorder()
    let tool = makeTool(
      bodyBatchSize: 2,
      bodyLookup: { noteIDs in
        await recorder.record(ids: noteIDs)
        return [
          "note-2": "example",
          "note-3": "example"
        ]
      }
    )

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("example"),
          "searchIn": .string("body"),
          "orderBy": .string("modified"),
          "orderDirection": .string("recent"),
          "limit": .int(2)
        ]
      )
    )

    let batches = await recorder.recordedBatches()
    #expect(batches.count == 1)
    #expect(batches[0] == ["note-2", "note-3"])
  }

  @Test
  func executeThrowsValidationErrorForSearchInWithoutSearchText() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["searchIn": .string("body")]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'searchIn' requires 'searchText'"))
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptySearchText() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["searchText": .string("   ")]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("non-empty string"))
    }
  }

  @Test
  func executeThrowsValidationErrorForOffsetWithoutLimit() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["offset": .int(1)]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("requires a positive 'limit'"))
    }
  }

  @Test
  func executeThrowsValidationErrorForNegativeOffset() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "offset": .int(-1),
            "limit": .int(1)
          ]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("non-negative integer"))
    }
  }

  @Test
  func executeThrowsValidationErrorForNegativeLimit() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["limit": .int(-1)]
        )
      )
      Issue.record("Expected validation error for negative limit")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("non-negative"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidOrderByValue() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["orderBy": .string("name")]
        )
      )
      Issue.record("Expected validation error for invalid orderBy")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'modified' or 'created'"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidSearchInValue() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "searchText": .string("example"),
            "searchIn": .string("metadata")
          ]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'title', 'body', or 'all'"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidIncludeBodyType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["includeBody": .string("true")]
        )
      )
      Issue.record("Expected validation error for invalid includeBody")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("expected a boolean"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidBodyFormatType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["bodyFormat": .int(1)]
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
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["bodyFormat": .string("rich")]
        )
      )
      Issue.record("Expected validation error for invalid bodyFormat value")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("expected 'plain', 'markdown', or 'html'"))
    }
  }

  @Test
  func executeReturnsMarkdownWhenBodyFormatIsMarkdown() async throws {
    let bodiesByID = defaultBodiesByID
    let tool = makeTool(
      bodyLookup: { noteIDs in
        var result: [String: String] = [:]
        for id in noteIDs {
          if let body = bodiesByID[id] {
            result[id] = body
          }
        }
        return result
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "includeBody": .bool(true),
          "bodyFormat": .string("markdown"),
          "limit": .int(1)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.count == 1)
    #expect(notes[0].body == "Kickoff **agenda**")
  }

  @Test
  func executeReturnsRawHTMLWhenBodyFormatIsHTML() async throws {
    let bodiesByID = defaultBodiesByID
    let tool = makeTool(
      bodyLookup: { noteIDs in
        var result: [String: String] = [:]
        for id in noteIDs {
          if let body = bodiesByID[id] {
            result[id] = body
          }
        }
        return result
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "includeBody": .bool(true),
          "bodyFormat": .string("html"),
          "limit": .int(1)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.count == 1)
    #expect(notes[0].body == "<div><h1>Standup Recap</h1></div><div><br></div><div>Kickoff <b>agenda</b></div>")
  }

  @Test
  func executeIgnoresBodyFormatWhenIncludeBodyIsFalse() async throws {
    let tool = makeTool()

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["bodyFormat": .string("markdown")]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.allSatisfy { $0.body == nil })
  }

  @Test
  func executeThrowsFolderValidationErrorForInvalidFolderType() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["folder": .int(1)]
        )
      )
      Issue.record("Expected folder validation error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidFolderType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsFolderValidationErrorForEmptyFolder() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["folder": .string("   ")]
        )
      )
      Issue.record("Expected folder validation error")
    } catch let error as Error.FolderResolution {
      #expect(error == .emptyFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeThrowsFolderValidationErrorForInvalidFolderPathFormat() async {
    let tool = makeTool()

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["folder": .string("Work//Sub")]
        )
      )
      Issue.record("Expected folder path format validation error")
    } catch let error as Error.FolderResolution {
      #expect(error == .invalidFolderPathFormat("Work//Sub"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeBuildsSpecificFolderMetadataScriptFromTrimmedPath() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "account": .string("  iCloud  "),
          "folder": .string("  Work  ")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set fullPath to \"Work\""))
    #expect(source.contains("set folderLeaf to \"Work\""))
  }

  @Test
  func executeBuildsSpecificNestedFolderMetadataScriptWithPathSegments() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "account": .string("iCloud"),
          "folder": .string("Jokes/IT/Deep")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set pathSegments to {\"Jokes\", \"IT\", \"Deep\"}"))
    #expect(source.contains("set fullPath to \"Jokes/IT/Deep\""))
    #expect(source.contains("set folderLeaf to \"Deep\""))
  }

  @Test
  func executeBuildsAccountOnlyMetadataScript() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["account": .string("iCloud")]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("tell targetAccount"))
    #expect(!source.contains("set pathSegments to"))
  }

  @Test
  func executeUsesFastMetadataScriptForSimpleLimitQuery() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["limit": .int(2)]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set maxCount to 2"))
    #expect(source.contains("set startIndex to 1"))
    #expect(source.contains("if accountName is \"\" then"))
    #expect(source.contains("set totalCount to count of notes"))
    #expect(source.contains("repeat with i from startIndex to endIndex"))
    #expect(!source.contains("repeat with n in every note"))
  }

  @Test
  func executeUsesFastMetadataScriptWhenOffsetIsProvided() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "limit": .int(2),
          "offset": .int(1)
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set startIndex to 2"))
    #expect(source.contains("set maxCount to 2"))
    #expect(source.contains("repeat with i from startIndex to endIndex"))
    #expect(!source.contains("repeat with n in every note"))
  }

  @Test
  func executeFastPathOffsetLimitReturnsExpectedWindow() async throws {
    let sourceStore = ScriptSourceStore()
    let notesInput = sampleNotesInput
    let tool = Tool.ListNotes(
      appleScriptFactory: { source in
        sourceStore.set(source)
        let windowedNotes = extractFastPathWindow(from: source, notes: notesInput)
        return StaticAppleScriptExecutor(notes: windowedNotes)
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "limit": .int(2),
          "offset": .int(1)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
    #expect(sourceStore.value().contains("set startIndex to 2"))
  }

  @Test
  func executeDoesNotUseFastMetadataScriptWhenOrderDirectionIsProvided() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "limit": .int(2),
          "orderDirection": .string("oldest")
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("repeat with n in every note"))
    #expect(!source.contains("repeat with i from 1 to maxCount"))
  }

  @Test
  func executeUsesFastMetadataScriptForAccountScopedLimitQuery() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "account": .string("iCloud"),
          "limit": .int(3)
        ]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set accountName to \"iCloud\""))
    #expect(source.contains("set totalCount to count of notes of targetAccount"))
    #expect(source.contains("set n to note i of targetAccount"))
    #expect(!source.contains("repeat with n in every note"))
  }

  @Test
  func executeBuildsSearchAllFolderMetadataScriptWhenFolderNameOnlyProvided() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["folder": .string("Work")]
      )
    )

    let source = sourceStore.value()
    #expect(source.contains("set matchingFolders to {}"))
    #expect(source.contains("set fullPath to \"Work\""))
    #expect(source.contains("set folderLeaf to \"Work\""))
    #expect(source.contains(FolderScriptErrorPrefix.folderAmbiguous))
  }

  @Test
  func executeAppliesFolderScopeBeforeBodySearchAndIncludeBody() async throws {
    let sourceStore = ScriptSourceStore()
    let allNotes = sampleNotesInput
    let inboxNotes = allNotes.filter { $0.folder == "Inbox" }
    let bodiesByID = defaultBodiesByID

    let tool = Tool.ListNotes(
      appleScriptFactory: { source in
        sourceStore.set(source)
        if source.contains("set folderLeaf to \"Inbox\"") {
          return StaticAppleScriptExecutor(notes: inboxNotes)
        }
        return StaticAppleScriptExecutor(notes: allNotes)
      },
      bodyLookup: { noteIDs in
        var lookup: [String: String] = [:]
        for id in noteIDs {
          if let body = bodiesByID[id] {
            lookup[id] = body
          }
        }
        return lookup
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "folder": .string("Inbox"),
          "searchText": .string("example"),
          "searchIn": .string("body"),
          "includeBody": .bool(true),
          "limit": .int(5)
        ]
      )
    )

    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2"])
    #expect(notes[0].body == "Contains callback example")
    #expect(sourceStore.value().contains("set folderLeaf to \"Inbox\""))
  }

  @Test
  func executeMapsStructuredFolderErrorFromMetadataExecution() async {
    let tool = Tool.ListNotes(
      appleScriptFactory: { _ in
        ThrowingAppleScriptExecutor(
          error: Error.AppleScript.custom(info: "MCP_FOLDER_NOT_FOUND::Work")
        )
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["folder": .string("Work")]
        )
      )
      Issue.record("Expected mapped folder error")
    } catch let error as Error.FolderResolution {
      #expect(error == .folderNotFound(segment: "Work", path: "Work"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredAccountErrorFromMetadataExecution() async {
    let tool = Tool.ListNotes(
      appleScriptFactory: { _ in
        ThrowingAppleScriptExecutor(
          error: Error.AppleScript.custom(info: "MCP_ACCOUNT_NOT_FOUND::iCloud")
        )
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "account": .string("iCloud"),
            "folder": .string("Work")
          ]
        )
      )
      Issue.record("Expected mapped account error")
    } catch let error as Error.FolderResolution {
      #expect(error == .accountNotFound("iCloud"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executeMapsStructuredAmbiguousFolderErrorFromMetadataExecution() async {
    let tool = Tool.ListNotes(
      appleScriptFactory: { _ in
        ThrowingAppleScriptExecutor(
          error: Error.AppleScript.custom(info: "MCP_FOLDER_AMBIGUOUS::Work::iCloud||On My Mac")
        )
      }
    )

    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["folder": .string("Work")]
        )
      )
      Issue.record("Expected mapped ambiguous folder error")
    } catch let error as Error.FolderResolution {
      #expect(error == .ambiguousFolder(path: "Work", accounts: ["iCloud", "On My Mac"]))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func executePropagatesMetadataExecutorErrors() async {
    let tool = Tool.ListNotes(
      appleScriptExecutor: ThrowingAppleScriptExecutor(
        error: ListNotesToolTestError(message: "script failed")
      )
    )

    await #expect(throws: ListNotesToolTestError.self) {
      _ = try await tool.execute(using: CallToolParameterFactory.make(name: Tool.ListNotes.name))
    }
  }

  @Test
  func executePropagatesBodyLookupErrors() async {
    let tool = makeTool(
      bodyLookup: { _ in
        throw ListNotesToolTestError(message: "body lookup failed")
      }
    )

    await #expect(throws: ListNotesToolTestError.self) {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "searchText": .string("example"),
            "searchIn": .string("body"),
            "limit": .int(1)
          ]
        )
      )
    }
  }

  @Test
  func executeStopsBeforeSecondBodyBatchWhenTaskIsCancelled() async throws {
    let gate = BodyLookupCancellationGate()
    let tool = makeTool(
      bodyBatchSize: 1,
      bodyLookup: { noteIDs in
        await gate.recordAndPauseIfFirstCall()
        var lookup: [String: String] = [:]
        for id in noteIDs {
          lookup[id] = "<div>no match</div>"
        }
        return lookup
      }
    )

    let task = Task {
      try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "searchText": .string("missing-term"),
            "searchIn": .string("body")
          ]
        )
      )
    }

    await gate.waitForFirstCall()
    task.cancel()
    await gate.resumeFirstCall()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }

    let totalCalls = await gate.callCount()
    #expect(totalCalls == 1)
  }

  // MARK: - Date Filter Behavior Tests

  @Test
  func executeFiltersNotesCreatedAfterDate() async throws {
    let tool = makeTool()
    // note-1 createdAt=100 (1970-01-01T00:01:40.000Z)
    // note-2 createdAt=200 (1970-01-01T00:03:20.000Z)
    // note-3 createdAt=300 (1970-01-01T00:05:00.000Z)
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdAfter": .string("1970-01-01T00:03:20.000Z")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
  }

  @Test
  func executeFiltersNotesCreatedBeforeDate() async throws {
    let tool = makeTool()
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdBefore": .string("1970-01-01T00:03:20.000Z")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1", "note-2"])
  }

  @Test
  func executeFiltersNotesModifiedAfterDate() async throws {
    let tool = makeTool()
    // note-1 modifiedAt=100 (1970-01-01T00:01:40.000Z)
    // note-2 modifiedAt=300 (1970-01-01T00:05:00.000Z)
    // note-3 modifiedAt=200 (1970-01-01T00:03:20.000Z)
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["modifiedAfter": .string("1970-01-01T00:03:20.000Z")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
  }

  @Test
  func executeFiltersNotesModifiedBeforeDate() async throws {
    let tool = makeTool()
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["modifiedBefore": .string("1970-01-01T00:01:40.000Z")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1"])
  }

  @Test
  func executeFiltersNotesByCreatedDateRange() async throws {
    let tool = makeTool()
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "createdAfter": .string("1970-01-01T00:01:40.000Z"),
          "createdBefore": .string("1970-01-01T00:03:20.000Z")
        ]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-1", "note-2"])
  }

  @Test
  func executeCreatedAfterEqualsCreatedBeforeMatchesExactTimestamp() async throws {
    let tool = makeTool()
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "createdAfter": .string("1970-01-01T00:03:20.000Z"),
          "createdBefore": .string("1970-01-01T00:03:20.000Z")
        ]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2"])
  }

  @Test
  func executeDateFilterCombinesWithSearchText() async throws {
    let tool = makeTool()
    // Search for "standup" in title (matches note-1) with date filter that includes all notes.
    // Then restrict createdAfter to exclude note-1.
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "searchText": .string("standup"),
          "createdAfter": .string("1970-01-01T00:03:00.000Z")
        ]
      )
    )
    let notes = try decodeNotes(from: result)
    // note-1 title matches "standup" but createdAt=100 < threshold, so excluded.
    #expect(notes.isEmpty)
  }

  @Test
  func executeDateFilterCombinesWithPagination() async throws {
    let tool = makeTool()
    // Filter leaves note-2 and note-3, then paginate with offset=1, limit=1.
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "createdAfter": .string("1970-01-01T00:03:20.000Z"),
          "limit": .int(1),
          "offset": .int(1)
        ]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-3"])
  }

  @Test
  func executeDateOnlyBeforeIncludesSameDayNotes() async throws {
    let tool = makeTool()
    // All sample notes are on 1970-01-01. Date-only "1970-01-01" as createdBefore
    // should normalize to end-of-day (1970-01-01T23:59:59.999Z), including all notes.
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdBefore": .string("1970-01-01")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.count == 3)
  }

  @Test
  func executeDateFilterAcceptsDateOnlyFormat() async throws {
    let tool = makeTool()
    // Date-only "1970-01-01" as createdAfter normalizes to start-of-day (1970-01-01T00:00:00.000Z).
    // All notes are at 100s, 200s, 300s into the day, so all pass.
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdAfter": .string("1970-01-01")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.count == 3)
  }

  @Test
  func executeDateFilterAcceptsNoFractionalSeconds() async throws {
    let tool = makeTool()
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdAfter": .string("1970-01-01T00:03:20Z")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
  }

  @Test
  func executeDateFilterAcceptsTimezoneOffset() async throws {
    let tool = makeTool()
    // 1970-01-01T02:03:20+02:00 == 1970-01-01T00:03:20Z
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdAfter": .string("1970-01-01T02:03:20+02:00")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-2", "note-3"])
  }

  @Test
  func executeDateFilterExcludesNotesWithEmptyTimestamps() async throws {
    let noteWithEmptyCreatedAt = [
      NoteMetadataDescriptorInput(
        id: "note-empty",
        title: "Empty Date",
        createdAt: nil,
        modifiedAt: Date(timeIntervalSince1970: 200),
        folder: "Inbox"
      ),
      NoteMetadataDescriptorInput(
        id: "note-valid",
        title: "Valid Date",
        createdAt: Date(timeIntervalSince1970: 200),
        modifiedAt: Date(timeIntervalSince1970: 200),
        folder: "Inbox"
      )
    ]

    let tool = Tool.ListNotes(
      appleScriptFactory: { _ in
        StaticAppleScriptExecutor(notes: noteWithEmptyCreatedAt)
      }
    )

    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: ["createdAfter": .string("1970-01-01")]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-valid"])
  }

  @Test
  func executeDateFilterDisablesFastPath() async throws {
    let sourceStore = ScriptSourceStore()
    let tool = makeTool(sourceStore: sourceStore)

    _ = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "limit": .int(2),
          "createdAfter": .string("1970-01-01")
        ]
      )
    )

    let source = sourceStore.value()
    // Fast path uses "repeat with i from startIndex", full path uses "repeat with n in every note".
    #expect(source.contains("repeat with n in every note"))
    #expect(!source.contains("set maxCount to"))
  }

  // MARK: - Date Filter Validation Tests

  @Test
  func executeThrowsValidationErrorForInvalidCreatedAfterType() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["createdAfter": .int(1)]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'createdAfter'"))
      #expect(message.contains("expected an ISO8601 date string"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidCreatedAfterValue() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["createdAfter": .string("not-a-date")]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'createdAfter'"))
      #expect(message.contains("not-a-date"))
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyCreatedAfter() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["createdAfter": .string("")]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'createdAfter'"))
      #expect(message.contains("ISO8601"))
    }
  }

  @Test
  func executeThrowsValidationErrorForContradictoryCreatedRange() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "createdAfter": .string("1970-01-02"),
            "createdBefore": .string("1970-01-01")
          ]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'createdAfter' must not be later than 'createdBefore'"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidModifiedAfterType() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["modifiedAfter": .int(1)]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'modifiedAfter'"))
      #expect(message.contains("expected an ISO8601 date string"))
    }
  }

  @Test
  func executeThrowsValidationErrorForInvalidModifiedAfterValue() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["modifiedAfter": .string("not-a-date")]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'modifiedAfter'"))
      #expect(message.contains("not-a-date"))
    }
  }

  @Test
  func executeThrowsValidationErrorForEmptyModifiedAfter() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: ["modifiedAfter": .string("")]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'modifiedAfter'"))
      #expect(message.contains("ISO8601"))
    }
  }

  @Test
  func executeThrowsValidationErrorForContradictoryModifiedRange() async {
    let tool = makeTool()
    do {
      _ = try await tool.execute(
        using: CallToolParameterFactory.make(
          name: Tool.ListNotes.name,
          arguments: [
            "modifiedAfter": .string("1970-01-02"),
            "modifiedBefore": .string("1970-01-01")
          ]
        )
      )
      Issue.record("Expected validation error")
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      #expect(message.contains("'modifiedAfter' must not be later than 'modifiedBefore'"))
    }
  }

  @Test
  func executeDateFilterCombinesCreatedAndModifiedFilters() async throws {
    let tool = makeTool()
    // note-1: createdAt=100, modifiedAt=100
    // note-2: createdAt=200, modifiedAt=300
    // note-3: createdAt=300, modifiedAt=200
    // Filter: createdAfter=200 AND modifiedBefore=250
    // note-2: created=200 >= 200 ✓, modified=300 <= 250? ✗
    // note-3: created=300 >= 200 ✓, modified=200 <= 250? ✓
    let result = try await tool.execute(
      using: CallToolParameterFactory.make(
        name: Tool.ListNotes.name,
        arguments: [
          "createdAfter": .string("1970-01-01T00:03:20.000Z"),
          "modifiedBefore": .string("1970-01-01T00:04:10.000Z")
        ]
      )
    )
    let notes = try decodeNotes(from: result)
    #expect(notes.map { $0.id } == ["note-3"])
  }

  private func makeTool(
    bodyBatchSize: Int = 50,
    sourceStore: ScriptSourceStore? = nil,
    bodyLookup: (@Sendable ([String]) async throws -> [String: String])? = nil
  ) -> AppleNotesMCP.Tool.ListNotes {
    let notesInput = sampleNotesInput
    let defaultBodiesByID = self.defaultBodiesByID
    let resolvedBodyLookup = bodyLookup ?? { noteIDs in
      var lookup: [String: String] = [:]
      for id in noteIDs {
        if let body = defaultBodiesByID[id] {
          lookup[id] = body
        }
      }
      return lookup
    }

    return Tool.ListNotes(
      appleScriptFactory: { source in
        sourceStore?.set(source)
        return StaticAppleScriptExecutor(notes: notesInput)
      },
      bodyBatchSize: bodyBatchSize,
      bodyLookup: resolvedBodyLookup
    )
  }

  private func decodeNotes(from result: CallTool.Result) throws -> [Models.Note] {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let jsonData = try #require(payload.data(using: String.Encoding.utf8))
    return try JSONDecoder().decode([Models.Note].self, from: jsonData)
  }

  private var sampleNotesInput: [NoteMetadataDescriptorInput] {
    [
      NoteMetadataDescriptorInput(
        id: "note-1",
        title: "Standup Recap",
        createdAt: Date(timeIntervalSince1970: 100),
        modifiedAt: Date(timeIntervalSince1970: 100),
        folder: "Inbox"
      ),
      NoteMetadataDescriptorInput(
        id: "note-2",
        title: "Quarterly Plan",
        createdAt: Date(timeIntervalSince1970: 200),
        modifiedAt: Date(timeIntervalSince1970: 300),
        folder: "Inbox"
      ),
      NoteMetadataDescriptorInput(
        id: "note-3",
        title: "Comedy Ideas",
        createdAt: Date(timeIntervalSince1970: 300),
        modifiedAt: Date(timeIntervalSince1970: 200),
        folder: "Archive"
      )
    ]
  }

  private var defaultBodiesByID: [String: String] {
    [
      "note-1": "<div><h1>Standup Recap</h1></div><div><br></div><div>Kickoff <b>agenda</b></div>",
      "note-2": "<div><h1>Quarterly Plan</h1></div><div><br></div><div>Contains callback example</div>",
      "note-3": "<div><h1>Comedy Ideas</h1></div><div><br></div><div><i>Standup</i> open mic example</div>"
    ]
  }
}

private struct StaticAppleScriptExecutor: AppleScriptExecuting {
  let notes: [NoteMetadataDescriptorInput]

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    DescriptorBuilders.makeNotesDescriptor(notes)
  }
}

private struct ThrowingAppleScriptExecutor: AppleScriptExecuting {
  let error: any Swift.Error & Sendable

  @MainActor
  func run() throws -> NSAppleEventDescriptor {
    throw error
  }
}

private actor BodyLookupRecorder {
  private var batches: [[String]] = []

  func record(ids: [String]) {
    batches.append(ids)
  }

  func recordedBatches() -> [[String]] {
    batches
  }
}

private actor BodyLookupCancellationGate {
  private var calls = 0
  private var firstCallReached: CheckedContinuation<Void, Never>?
  private var releaseFirstCall: CheckedContinuation<Void, Never>?

  func recordAndPauseIfFirstCall() async {
    calls += 1
    if calls == 1 {
      firstCallReached?.resume()
      firstCallReached = nil
      await withCheckedContinuation { continuation in
        releaseFirstCall = continuation
      }
    }
  }

  func waitForFirstCall() async {
    if calls >= 1 {
      return
    }
    await withCheckedContinuation { continuation in
      firstCallReached = continuation
    }
  }

  func resumeFirstCall() {
    releaseFirstCall?.resume()
    releaseFirstCall = nil
  }

  func callCount() -> Int {
    calls
  }
}

private struct ListNotesToolTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}

private func extractFastPathWindow(
  from source: String,
  notes: [NoteMetadataDescriptorInput]
) -> [NoteMetadataDescriptorInput] {
  let startIndex = extractAppleScriptInteger(from: source, prefix: "set startIndex to ") ?? 1
  let maxCount = extractAppleScriptInteger(from: source, prefix: "set maxCount to ") ?? notes.count
  let zeroBasedStart = max(startIndex - 1, 0)
  return Array(notes.dropFirst(zeroBasedStart).prefix(max(maxCount, 0)))
}

private func extractAppleScriptInteger(from source: String, prefix: String) -> Int? {
  guard let range = source.range(of: prefix) else {
    return nil
  }

  let suffix = source[range.upperBound...]
  let digits = suffix.prefix { $0.isNumber }
  guard !digits.isEmpty else {
    return nil
  }
  return Int(digits)
}
