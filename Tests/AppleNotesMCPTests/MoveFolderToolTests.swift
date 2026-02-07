import Foundation
import MCP
import Testing
import AppleNotesMCPTestSupport
@testable import AppleNotesMCP

@Suite("Move Folder Tool")
struct MoveFolderToolTests {

  // MARK: - Test Helpers

  private static func makeOperations(
    listFolders: (@Sendable (_ account: String?) async throws -> [Models.Folder])? = nil,
    listNotes: (@Sendable (_ account: String, _ folderPath: String) async throws -> [Models.Note])? = nil,
    createFolder: (@Sendable (_ account: String, _ folderPath: String) async throws -> Models.CreateFolderResult)? = nil,
    moveNote: (@Sendable (_ noteID: String, _ account: String, _ folderPath: String) async throws -> Models.MoveNoteResult)? = nil,
    deleteFolder: (@Sendable (_ account: String, _ folderPath: String) async throws -> Models.DeleteFolderResult)? = nil
  ) -> AppleNotesMCP.Tool.MoveFolder.Operations {
    AppleNotesMCP.Tool.MoveFolder.Operations(
      listFolders: listFolders ?? { _ in [] },
      listNotes: listNotes ?? { _, _ in [] },
      createFolder: createFolder ?? { account, path in
        Models.CreateFolderResult(account: account, path: path, name: path.components(separatedBy: "/").last ?? path, parentPath: "", depth: 0, alreadyExisted: false)
      },
      moveNote: moveNote ?? { id, account, path in
        Models.MoveNoteResult(id: id, title: "", account: account, path: path, folder: path.components(separatedBy: "/").last ?? path, modifiedAt: "2025-01-01T00:00:00Z")
      },
      deleteFolder: deleteFolder ?? { account, path in
        Models.DeleteFolderResult(account: account, path: path, folder: path.components(separatedBy: "/").last ?? path, deleted: true)
      }
    )
  }

  private func decodePayload(from result: CallTool.Result) throws -> Models.MoveFolderResult {
    let payload = try #require(ResultHelpers.firstText(in: result))
    let data = try #require(payload.data(using: .utf8))
    return try JSONDecoder().decode(Models.MoveFolderResult.self, from: data)
  }

  private static func makeParams(
    folder: String? = nil,
    destinationFolder: String? = nil,
    account: String? = nil,
    destinationAccount: String? = nil
  ) -> CallTool.Parameters {
    var arguments: [String: MCP.Value] = [:]
    if let folder { arguments["folder"] = .string(folder) }
    if let destinationFolder { arguments["destinationFolder"] = .string(destinationFolder) }
    if let account { arguments["account"] = .string(account) }
    if let destinationAccount { arguments["destinationAccount"] = .string(destinationAccount) }
    return CallToolParameterFactory.make(name: Tool.MoveFolder.name, arguments: arguments)
  }

  // MARK: - Argument Parsing

  @Test
  func throwsForMissingFolder() async {
    let tool = Tool.MoveFolder(operations: Self.makeOperations())

    do {
      _ = try await tool.execute(using: Self.makeParams(destinationFolder: "Archive"))
      Issue.record("Expected missingFolder error")
    } catch let error as Error.MoveFolder {
      #expect(error == .missingFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func throwsForMissingDestinationFolder() async {
    let tool = Tool.MoveFolder(operations: Self.makeOperations())

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work"))
      Issue.record("Expected missingDestinationFolder error")
    } catch let error as Error.MoveFolder {
      #expect(error == .missingDestinationFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func throwsForInvalidDestinationFolderPathFormat() async {
    let tool = Tool.MoveFolder(operations: Self.makeOperations())

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "/Archive"))
      Issue.record("Expected invalidDestinationFolderPathFormat error")
    } catch let error as Error.MoveFolder {
      #expect(error == .invalidDestinationFolderPathFormat("/Archive"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func throwsForInvalidDestinationAccountType() async {
    let tool = Tool.MoveFolder(operations: Self.makeOperations())
    let params = CallToolParameterFactory.make(
      name: Tool.MoveFolder.name,
      arguments: [
        "folder": .string("Work"),
        "destinationFolder": .string("Archive"),
        "destinationAccount": .int(42)
      ]
    )

    do {
      _ = try await tool.execute(using: params)
      Issue.record("Expected invalidDestinationAccountType error")
    } catch let error as Error.MoveFolder {
      #expect(error == .invalidDestinationAccountType)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func throwsForEmptyDestinationFolder() async {
    let tool = Tool.MoveFolder(operations: Self.makeOperations())

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "  "))
      Issue.record("Expected emptyDestinationFolder error")
    } catch let error as Error.MoveFolder {
      #expect(error == .emptyDestinationFolder)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func throwsForEmptyDestinationAccount() async {
    let tool = Tool.MoveFolder(operations: Self.makeOperations())

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive", destinationAccount: "  "))
      Issue.record("Expected emptyDestinationAccount error")
    } catch let error as Error.MoveFolder {
      #expect(error == .emptyDestinationAccount)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  // MARK: - Source Resolution

  @Test
  func resolvesSourceFromListFolders() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { account in
        store.append(account ?? "<nil>")
        return [
          Models.Folder(account: "iCloud", path: "Work/Projects", name: "Projects", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "Work/Projects",
      destinationFolder: "Archive",
      account: "iCloud"
    ))

    #expect(store.values == ["iCloud"])
    let payload = try decodePayload(from: result)
    #expect(payload.sourceAccount == "iCloud")
    #expect(payload.sourcePath == "Work/Projects")
  }

  @Test
  func throwsSourceFolderNotFoundWhenPathAbsent() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Missing", destinationFolder: "Archive"))
      Issue.record("Expected sourceFolderNotFound error")
    } catch let error as Error.MoveFolder {
      #expect(error == .sourceFolderNotFound("Missing"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func throwsSourceFolderAmbiguousWhenPathInMultipleAccounts() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "On My Mac", path: "Work", name: "Work", parentPath: "", depth: 0)
        ]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
      Issue.record("Expected sourceFolderAmbiguous error")
    } catch let error as Error.MoveFolder {
      #expect(error == .sourceFolderAmbiguous("Work", ["On My Mac", "iCloud"]))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func scopesListFoldersToAccountWhenProvided() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { account in
        store.append(account ?? "<nil>")
        return [Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    _ = try await tool.execute(using: Self.makeParams(
      folder: "Work",
      destinationFolder: "Archive",
      account: "iCloud"
    ))

    #expect(store.values == ["iCloud"])
  }

  // MARK: - Validation

  @Test
  func rejectsCycleMoveWhereDestinationContainsSource() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      // destinationRootPath = "Work/Work", sourcePath = "Work"
      // "Work/Work".hasPrefix("Work/") == true => cycle detected
      _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Work"))
      Issue.record("Expected invalidMoveTarget error")
    } catch let error as Error.MoveFolder {
      #expect(error == .invalidMoveTarget("Destination cannot be the source folder or any of its descendants."))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func rejectsCycleMoveWhereDestinationIsDescendant() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Work/Projects", name: "Projects", parentPath: "Work", depth: 1)
        ]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Work/Projects"))
      Issue.record("Expected invalidMoveTarget error")
    } catch let error as Error.MoveFolder {
      #expect(error == .invalidMoveTarget("Destination cannot be the source folder or any of its descendants."))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func rejectsNoOpMoveToCurrentParent() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work/Projects", name: "Projects", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)
        ]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Work/Projects", destinationFolder: "Work"))
      Issue.record("Expected noOpMove error")
    } catch let error as Error.MoveFolder {
      #expect(error == .noOpMove)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func skipsCycleCheckForCrossAccountMoves() async throws {
    let ops = Self.makeOperations(
      listFolders: { account in
        if account == "iCloud" {
          return [
            Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)
          ]
        }
        return []
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "Work",
      destinationFolder: "Work/Sub",
      account: "iCloud",
      destinationAccount: "On My Mac"
    ))

    #expect(result.isError == false)
  }

  @Test
  func rejectsSystemFolderNotes() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [Models.Folder(account: "iCloud", path: "Notes", name: "Notes", parentPath: "", depth: 0)]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Notes", destinationFolder: "Archive"))
      Issue.record("Expected cannotModifySystemFolder error")
    } catch let error as Error.MoveFolder {
      #expect(error == .cannotModifySystemFolder("Notes"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func rejectsSystemFolderRecentlyDeleted() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [Models.Folder(account: "iCloud", path: "Recently Deleted", name: "Recently Deleted", parentPath: "", depth: 0)]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(folder: "Recently Deleted", destinationFolder: "Archive"))
      Issue.record("Expected cannotModifySystemFolder error")
    } catch let error as Error.MoveFolder {
      #expect(error == .cannotModifySystemFolder("Recently Deleted"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func allowsNonTopLevelFolderNamedNotes() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work/Notes", name: "Notes", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "Work/Notes",
      destinationFolder: "Archive"
    ))

    #expect(result.isError == false)
  }

  // MARK: - Folder Creation

  @Test
  func createsTreeInTopDownOrder() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Work/Sub", name: "Sub", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Work/Sub/Deep", name: "Deep", parentPath: "Work/Sub", depth: 2),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      createFolder: { account, path in
        store.append(path)
        return Models.CreateFolderResult(
          account: account,
          path: path,
          name: path.components(separatedBy: "/").last ?? path,
          parentPath: "",
          depth: 0,
          alreadyExisted: false
        )
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))

    #expect(store.values == ["Archive/Work", "Archive/Work/Sub", "Archive/Work/Sub/Deep"])
  }

  @Test
  func mapsPathsCorrectlyForSubfolders() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "A/B", name: "B", parentPath: "A", depth: 1),
          Models.Folder(account: "iCloud", path: "A/B/C", name: "C", parentPath: "A/B", depth: 2),
          Models.Folder(account: "iCloud", path: "A", name: "A", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "X", name: "X", parentPath: "", depth: 0)
        ]
      },
      createFolder: { account, path in
        store.append(path)
        return Models.CreateFolderResult(account: account, path: path, name: "", parentPath: "", depth: 0, alreadyExisted: false)
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    _ = try await tool.execute(using: Self.makeParams(folder: "A/B", destinationFolder: "X"))

    #expect(store.values == ["X/B", "X/B/C"])
  }

  @Test
  func createdFoldersOnlyIncludesNewlyCreated() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Work/Sub", name: "Sub", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      createFolder: { account, path in
        let existed = path == "Archive/Work"
        return Models.CreateFolderResult(account: account, path: path, name: "", parentPath: "", depth: 0, alreadyExisted: existed)
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.createdFolders == ["Archive/Work/Sub"])
  }

  // MARK: - Note Moving

  @Test
  func movesNotesFromAllSubfoldersToCorrectDestinations() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Work/Sub", name: "Sub", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, folderPath in
        if folderPath == "Work" {
          return [Models.Note(id: "n1", title: "Note1", body: nil, folder: "Work", createdAt: "", modifiedAt: "")]
        } else if folderPath == "Work/Sub" {
          return [Models.Note(id: "n2", title: "Note2", body: nil, folder: "Work/Sub", createdAt: "", modifiedAt: "")]
        }
        return []
      },
      moveNote: { id, account, folder in
        store.append("\(id):\(folder)")
        return Models.MoveNoteResult(id: id, title: "", account: account, path: folder, folder: folder, modifiedAt: "")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(store.values == ["n1:Archive/Work", "n2:Archive/Work/Sub"])
    #expect(payload.movedNoteCount == 2)
  }

  @Test
  func capturesFailedNoteMoves() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [
          Models.Note(id: "n1", title: "Good", body: nil, folder: "Work", createdAt: "", modifiedAt: ""),
          Models.Note(id: "n2", title: "Bad", body: nil, folder: "Work", createdAt: "", modifiedAt: "")
        ]
      },
      moveNote: { id, account, folder in
        if id == "n2" {
          throw MoveFolderTestError(message: "move failed")
        }
        return Models.MoveNoteResult(id: id, title: "", account: account, path: folder, folder: folder, modifiedAt: "")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.movedNoteCount == 1)
    #expect(payload.failedNoteMoves.count == 1)
    #expect(payload.failedNoteMoves[0].noteID == "n2")
    #expect(payload.failedNoteMoves[0].noteTitle == "Bad")
    #expect(payload.failedNoteMoves[0].sourceFolder == "Work")
    #expect(payload.failedNoteMoves[0].destinationFolder == "Archive/Work")
  }

  @Test
  func continuesAfterIndividualNoteFailure() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [
          Models.Note(id: "n1", title: "A", body: nil, folder: "Work", createdAt: "", modifiedAt: ""),
          Models.Note(id: "n2", title: "B", body: nil, folder: "Work", createdAt: "", modifiedAt: ""),
          Models.Note(id: "n3", title: "C", body: nil, folder: "Work", createdAt: "", modifiedAt: "")
        ]
      },
      moveNote: { id, account, folder in
        if id == "n2" {
          throw MoveFolderTestError(message: "move failed")
        }
        store.append(id)
        return Models.MoveNoteResult(id: id, title: "", account: account, path: folder, folder: folder, modifiedAt: "")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    _ = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))

    #expect(store.values == ["n1", "n3"])
  }

  // MARK: - Source Deletion

  @Test
  func deletesSourceWhenAllNotesMoved() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [Models.Note(id: "n1", title: "Note", body: nil, folder: "Work", createdAt: "", modifiedAt: "")]
      },
      deleteFolder: { _, path in
        store.append("deleted:\(path)")
        return Models.DeleteFolderResult(account: "iCloud", path: path, folder: "Work", deleted: true)
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(store.values == ["deleted:Work"])
    #expect(payload.sourceDeleted == true)
    #expect(payload.moved == true)
  }

  @Test
  func skipsDeleteOnPartialFailure() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [Models.Note(id: "n1", title: "Note", body: nil, folder: "Work", createdAt: "", modifiedAt: "")]
      },
      moveNote: { _, _, _ in
        throw MoveFolderTestError(message: "move failed")
      },
      deleteFolder: { _, path in
        store.append("deleted:\(path)")
        return Models.DeleteFolderResult(account: "iCloud", path: path, folder: "Work", deleted: true)
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(store.values.isEmpty)
    #expect(payload.sourceDeleted == false)
    #expect(payload.moved == false)
  }

  @Test
  func sourceDeletedFalseWhenDeleteFails() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [Models.Note(id: "n1", title: "Note", body: nil, folder: "Work", createdAt: "", modifiedAt: "")]
      },
      deleteFolder: { _, _ in
        throw MoveFolderTestError(message: "delete failed")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.sourceDeleted == false)
    #expect(payload.moved == false)
  }

  // MARK: - Result Payload

  @Test
  func fullSuccessResult() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work/Projects", name: "Projects", parentPath: "Work", depth: 1),
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, folderPath in
        if folderPath == "Work/Projects" {
          return [Models.Note(id: "n1", title: "Note1", body: nil, folder: "Work/Projects", createdAt: "", modifiedAt: "")]
        }
        return []
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "Work/Projects",
      destinationFolder: "Archive"
    ))
    let payload = try decodePayload(from: result)

    #expect(payload.moved == true)
    #expect(payload.partial == false)
    #expect(payload.sourceDeleted == true)
    #expect(payload.sourceAccount == "iCloud")
    #expect(payload.sourcePath == "Work/Projects")
    #expect(payload.destinationAccount == "iCloud")
    #expect(payload.destinationPath == "Archive/Projects")
    #expect(payload.folder == "Projects")
    #expect(payload.movedNoteCount == 1)
    #expect(payload.failedNoteMoves.isEmpty)
  }

  @Test
  func partialFailureResult() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [
          Models.Note(id: "n1", title: "Good", body: nil, folder: "Work", createdAt: "", modifiedAt: ""),
          Models.Note(id: "n2", title: "Bad", body: nil, folder: "Work", createdAt: "", modifiedAt: "")
        ]
      },
      moveNote: { id, account, folder in
        if id == "n2" { throw MoveFolderTestError(message: "failed") }
        return Models.MoveNoteResult(id: id, title: "", account: account, path: folder, folder: folder, modifiedAt: "")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.moved == false)
    #expect(payload.partial == true)
    #expect(payload.sourceDeleted == false)
    #expect(payload.movedNoteCount == 1)
    #expect(payload.failedNoteMoves.count == 1)
  }

  @Test
  func crossAccountPathsCorrect() async throws {
    let ops = Self.makeOperations(
      listFolders: { account in
        if account == "iCloud" {
          return [
            Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)
          ]
        }
        return []
      },
      listNotes: { _, _ in
        [Models.Note(id: "n1", title: "Note", body: nil, folder: "Work", createdAt: "", modifiedAt: "")]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "Work",
      destinationFolder: "Archive",
      account: "iCloud",
      destinationAccount: "On My Mac"
    ))
    let payload = try decodePayload(from: result)

    #expect(payload.sourceAccount == "iCloud")
    #expect(payload.destinationAccount == "On My Mac")
    #expect(payload.destinationPath == "Archive/Work")
  }

  // MARK: - Edge Cases

  @Test
  func emptySourceFolderNoNotesNoSubfolders() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Empty", name: "Empty", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in [] }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Empty", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.moved == true)
    #expect(payload.movedNoteCount == 0)
    #expect(payload.failedNoteMoves.isEmpty)
    #expect(payload.sourceDeleted == true)
  }

  @Test
  func sourceWithOnlySubfoldersRootHasNoNotes() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Parent", name: "Parent", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Parent/Child", name: "Child", parentPath: "Parent", depth: 1),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, folderPath in
        if folderPath == "Parent" {
          return []
        } else if folderPath == "Parent/Child" {
          return [Models.Note(id: "n1", title: "ChildNote", body: nil, folder: "Parent/Child", createdAt: "", modifiedAt: "")]
        }
        return []
      },
      moveNote: { id, account, folder in
        store.append("\(id):\(folder)")
        return Models.MoveNoteResult(id: id, title: "", account: account, path: folder, folder: folder, modifiedAt: "")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Parent", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.moved == true)
    #expect(store.values == ["n1:Archive/Parent/Child"])
  }

  @Test
  func allNotesMoveFailResultsInNotPartial() async throws {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      listNotes: { _, _ in
        [Models.Note(id: "n1", title: "Note", body: nil, folder: "Work", createdAt: "", modifiedAt: "")]
      },
      moveNote: { _, _, _ in
        throw MoveFolderTestError(message: "failed")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(folder: "Work", destinationFolder: "Archive"))
    let payload = try decodePayload(from: result)

    #expect(payload.moved == false)
    #expect(payload.partial == false)
    #expect(payload.movedNoteCount == 0)
    #expect(payload.failedNoteMoves.count == 1)
    #expect(payload.sourceDeleted == false)
  }

  // MARK: - Notes Destination Normalization

  @Test
  func notesDestinationNormalizesToRootForCrossAccount() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { account in
        if account == "iCloud" {
          return [
            Models.Folder(account: "iCloud", path: "TheInkedEngineer", name: "TheInkedEngineer", parentPath: "", depth: 0)
          ]
        }
        return []
      },
      createFolder: { account, path in
        store.append(path)
        return Models.CreateFolderResult(account: account, path: path, name: path, parentPath: "", depth: 0, alreadyExisted: false)
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "TheInkedEngineer",
      destinationFolder: "Notes",
      account: "iCloud",
      destinationAccount: "Google"
    ))
    let payload = try decodePayload(from: result)

    #expect(store.values == ["TheInkedEngineer"])
    #expect(payload.destinationPath == "TheInkedEngineer")
  }

  @Test
  func notesDestinationDetectsNoOpForDepthZeroSameAccount() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)]
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(
        folder: "Work",
        destinationFolder: "Notes",
        account: "iCloud"
      ))
      Issue.record("Expected noOpMove error")
    } catch let error as Error.MoveFolder {
      #expect(error == .noOpMove)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func archiveNotesPathIsNotNormalized() async throws {
    let store = CaptureStore()
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "iCloud", path: "Stuff", name: "Stuff", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive", name: "Archive", parentPath: "", depth: 0),
          Models.Folder(account: "iCloud", path: "Archive/Notes", name: "Notes", parentPath: "Archive", depth: 1)
        ]
      },
      createFolder: { account, path in
        store.append(path)
        return Models.CreateFolderResult(account: account, path: path, name: "", parentPath: "", depth: 0, alreadyExisted: false)
      }
    )

    let tool = Tool.MoveFolder(operations: ops)
    let result = try await tool.execute(using: Self.makeParams(
      folder: "Stuff",
      destinationFolder: "Archive/Notes"
    ))
    let payload = try decodePayload(from: result)

    #expect(store.values == ["Archive/Notes/Stuff"])
    #expect(payload.destinationPath == "Archive/Notes/Stuff")
  }

  @Test
  func createFolderNestedPathErrorIncludesNestingHint() async {
    let ops = Self.makeOperations(
      listFolders: { _ in
        [
          Models.Folder(account: "Google", path: "Work", name: "Work", parentPath: "", depth: 0),
          Models.Folder(account: "Google", path: "Archive", name: "Archive", parentPath: "", depth: 0)
        ]
      },
      createFolder: { _, path in
        throw MoveFolderTestError(message: "Folder creation failed")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(
        folder: "Work",
        destinationFolder: "Archive",
        account: "Google"
      ))
      Issue.record("Expected subToolFailed error")
    } catch let error as Error.MoveFolder {
      let message = error.localizedDescription
      #expect(message.contains("This account may not support nested folders."))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func createFolderFlatPathErrorOmitsNestingHint() async {
    let ops = Self.makeOperations(
      listFolders: { account in
        if account == "iCloud" {
          return [
            Models.Folder(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0)
          ]
        }
        return []
      },
      createFolder: { _, path in
        throw MoveFolderTestError(message: "Folder creation failed")
      }
    )

    let tool = Tool.MoveFolder(operations: ops)

    do {
      _ = try await tool.execute(using: Self.makeParams(
        folder: "Work",
        destinationFolder: "Notes",
        account: "iCloud",
        destinationAccount: "Google"
      ))
      Issue.record("Expected subToolFailed error")
    } catch let error as Error.MoveFolder {
      let message = error.localizedDescription
      #expect(!message.contains("This account may not support nested folders."))
      #expect(message.contains("Folder creation failed"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  // MARK: - Path Mapping Helper

  @Test
  func destinationPathForRootFolder() {
    let result = Tool.MoveFolder.destinationPath(for: "Work", sourceRoot: "Work", destinationRoot: "Archive/Work")
    #expect(result == "Archive/Work")
  }

  @Test
  func destinationPathForSubfolder() {
    let result = Tool.MoveFolder.destinationPath(for: "Work/Sub/Deep", sourceRoot: "Work", destinationRoot: "Archive/Work")
    #expect(result == "Archive/Work/Sub/Deep")
  }

  @Test
  func destinationPathForImmediateChild() {
    let result = Tool.MoveFolder.destinationPath(for: "Work/Child", sourceRoot: "Work", destinationRoot: "Archive/Work")
    #expect(result == "Archive/Work/Child")
  }
}

/// Thread-safe store for capturing values in `@Sendable` closures.
private final class CaptureStore: @unchecked Sendable {
  private let lock = NSLock()
  private var _values: [String] = []

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return _values
  }

  func append(_ value: String) {
    lock.lock()
    defer { lock.unlock() }
    _values.append(value)
  }
}

private struct MoveFolderTestError: LocalizedError, Sendable, Equatable {
  let message: String

  var errorDescription: String? {
    message
  }
}
