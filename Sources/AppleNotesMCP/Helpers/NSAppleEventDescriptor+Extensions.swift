import Foundation

/// Parsed payload for `batch_get_notes` script results.
struct BatchNoteLookupResult: Sendable {
  let notes: [Models.Note]
  let missingIDs: [String]
}

/// Parsed payload for `batch_delete_notes` script results.
struct BatchDeleteResult: Sendable {
  let deletedIDs: [String]
  let missingIDs: [String]
  let failed: [Models.BatchDeleteFailure]
}

extension NSAppleEventDescriptor {
  /// Parses account rows returned by `list_accounts` scripts.
  ///
  /// Expected shape:
  /// - list of strings, one per account name
  @MainActor
  func parseAccounts() -> [Models.Account] {
    var accounts: [Models.Account] = []

    let count = numberOfItems
    if count == 0 {
      if let singleName = stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
         !singleName.isEmpty {
        return [Models.Account(name: singleName)]
      }
      return accounts
    }

    for index in 1...count {
      guard let accountName = atIndex(index)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !accountName.isEmpty else {
        continue
      }
      accounts.append(Models.Account(name: accountName))
    }

    return accounts
  }

  /// Parses folder rows returned by `list_folders` scripts.
  ///
  /// Expected per item shape:
  /// `{account, fullPath, leafName, parentPath, depth}`
  @MainActor
  func parseFolders() -> [Models.Folder] {
    var folders: [Models.Folder] = []

    let count = numberOfItems
    if count == 0 {
      return folders
    }

    for index in 1...count {
      guard let folderDesc = atIndex(index),
            folderDesc.numberOfItems >= 5 else {
        continue
      }

      let account = folderDesc.atIndex(1)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let path = folderDesc.atIndex(2)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let name = folderDesc.atIndex(3)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let parentPath = folderDesc.atIndex(4)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let depth = parseDepth(from: folderDesc.atIndex(5))

      guard !account.isEmpty, !path.isEmpty, !name.isEmpty, depth >= 0 else {
        continue
      }

      folders.append(
        Models.Folder(
          account: account,
          path: path,
          name: name,
          parentPath: parentPath,
          depth: depth
        )
      )
    }

    return folders
  }

  /// Parses metadata rows returned by `list_notes` script.
  ///
  /// Expected per item shape:
  /// `{id, title, createdDate, modifiedDate, folder}`
  /// Optional item shape extension:
  /// `{id, title, createdDate, modifiedDate, folder, bodyHTML}`
  @MainActor
  func parseNotes() -> [Models.Note] {
    var notes: [Models.Note] = []

    let count = self.numberOfItems
    if count == 0 {
      return notes
    }

    for index in 1...count {
      guard let noteDesc = self.atIndex(index),
            noteDesc.numberOfItems >= 5 else {
        continue
      }

      let id = noteDesc.atIndex(1)?.stringValue ?? ""
      let metadataTitle = noteDesc.atIndex(2)?.stringValue ?? ""
      let bodyHTML = noteDesc.numberOfItems >= 6 ? noteDesc.atIndex(6)?.stringValue : nil
      let title = BodyFormatter.resolvedTitle(metadataTitle: metadataTitle, bodyHTML: bodyHTML)
      let createdDate = noteDesc.atIndex(3)?.dateValue
      let modifiedDate = noteDesc.atIndex(4)?.dateValue
      let folder = noteDesc.atIndex(5)?.stringValue ?? ""

      let createdAt = createdDate.map { $0.formatted(Date.notesTimestamp) } ?? ""
      let modifiedAt = modifiedDate.map { $0.formatted(Date.notesTimestamp) } ?? ""

      notes.append(
        Models.Note(
          id: id,
          title: title,
          body: nil,
          folder: folder,
          createdAt: createdAt,
          modifiedAt: modifiedAt
        )
      )
    }

    return notes
  }

  /// Parses a single note returned by `get_note`.
  ///
  /// Expected shape:
  /// `{id, title, bodyHTML, createdDate, modifiedDate, folder}`
  ///
  /// `body` is returned as raw HTML. Tool edges decide presentation format
  /// (plain text vs markdown) to keep parser behavior neutral.
  @MainActor
  func parseSingleNote() -> Models.Note? {
    guard numberOfItems == 6 else {
      return nil
    }

    let id = atIndex(1)?.stringValue ?? ""
    let metadataTitle = atIndex(2)?.stringValue ?? ""
    let bodyHTML = atIndex(3)?.stringValue ?? ""
    let title = BodyFormatter.resolvedTitle(metadataTitle: metadataTitle, bodyHTML: bodyHTML)
    let createdDate = atIndex(4)?.dateValue
    let modifiedDate = atIndex(5)?.dateValue
    let folder = atIndex(6)?.stringValue ?? ""

    let createdAt = createdDate.map { $0.formatted(Date.notesTimestamp) } ?? ""
    let modifiedAt = modifiedDate.map { $0.formatted(Date.notesTimestamp) } ?? ""

    return Models.Note(
      id: id,
      title: title,
      body: bodyHTML,
      folder: folder,
      createdAt: createdAt,
      modifiedAt: modifiedAt
    )
  }

  /// Parses move result returned by `move_note`.
  ///
  /// Expected shape:
  /// `{id, title, account, fullPath, folderLeaf, modifiedDate}`
  @MainActor
  func parseMoveResult() -> Models.MoveNoteResult? {
    guard numberOfItems == 6 else {
      return nil
    }

    let id = atIndex(1)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let title = atIndex(2)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let account = atIndex(3)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let path = atIndex(4)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let folder = atIndex(5)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let modifiedDate = atIndex(6)?.dateValue
    let modifiedAt = modifiedDate.map { $0.formatted(Date.notesTimestamp) } ?? ""

    guard !id.isEmpty,
          !account.isEmpty,
          !path.isEmpty,
          !folder.isEmpty else {
      return nil
    }

    return Models.MoveNoteResult(
      id: id,
      title: title,
      account: account,
      path: path,
      folder: folder,
      modifiedAt: modifiedAt
    )
  }

  /// Parses batch lookup result returned by `batch_get_notes`.
  ///
  /// Expected top-level shape:
  /// `{foundRows, missingIDs}`
  ///
  /// `foundRows` item shape:
  /// `{id, title, bodyHTML, createdDate, modifiedDate, folder}`
  @MainActor
  func parseBatchNoteLookupResult() -> BatchNoteLookupResult? {
    guard numberOfItems == 2,
          let foundRowsDescriptor = atIndex(1),
          let missingIDsDescriptor = atIndex(2) else {
      return nil
    }

    var notes: [Models.Note] = []
    let foundCount = foundRowsDescriptor.numberOfItems
    if foundCount > 0 {
      for index in 1...foundCount {
        guard let row = foundRowsDescriptor.atIndex(index),
              let parsedNote = row.parseSingleNote() else {
          continue
        }
        notes.append(parsedNote)
      }
    }

    var missingIDs: [String] = []
    let missingCount = missingIDsDescriptor.numberOfItems
    if missingCount > 0 {
      for index in 1...missingCount {
        guard let missingID = missingIDsDescriptor.atIndex(index)?
          .stringValue?
          .trimmingCharacters(in: .whitespacesAndNewlines),
          !missingID.isEmpty else {
          continue
        }
        missingIDs.append(missingID)
      }
    } else if let singleMissing = missingIDsDescriptor
      .stringValue?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !singleMissing.isEmpty {
      missingIDs.append(singleMissing)
    }

    return BatchNoteLookupResult(notes: notes, missingIDs: missingIDs)
  }

  /// Parses batch delete result returned by `batch_delete_notes`.
  ///
  /// Expected top-level shape:
  /// `{deletedIDs, missingIDs, failedRows}`
  ///
  /// `failedRows` item shape:
  /// `{id, reason}`
  @MainActor
  func parseBatchDeleteResult() -> BatchDeleteResult? {
    guard numberOfItems == 3,
          let deletedIDsDescriptor = atIndex(1),
          let missingIDsDescriptor = atIndex(2),
          let failedRowsDescriptor = atIndex(3) else {
      return nil
    }

    let deletedIDs = parseStringList(from: deletedIDsDescriptor)
    let missingIDs = parseStringList(from: missingIDsDescriptor)

    var failed: [Models.BatchDeleteFailure] = []
    let failedCount = failedRowsDescriptor.numberOfItems
    if failedCount > 0 {
      for index in 1...failedCount {
        guard let row = failedRowsDescriptor.atIndex(index),
              row.numberOfItems >= 2,
              let id = row.atIndex(1)?
                .stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else {
          continue
        }

        let reason = row.atIndex(2)?
          .stringValue?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedReason = reason.isEmpty ? "Unknown script error." : reason
        failed.append(.init(id: id, reason: normalizedReason))
      }
    }

    return BatchDeleteResult(
      deletedIDs: deletedIDs,
      missingIDs: missingIDs,
      failed: failed
    )
  }

  /// Parses body lookup rows.
  ///
  /// Expected per item shape:
  /// `{id, bodyHTML}`
  ///
  /// Values remain raw HTML so search/output paths can use different render
  /// formats without losing original body content.
  @MainActor
  func parseNoteBodies() -> [String: String] {
    var bodiesByID: [String: String] = [:]
    let count = numberOfItems
    if count == 0 {
      return bodiesByID
    }

    for index in 1...count {
      guard let bodyItem = atIndex(index),
            bodyItem.numberOfItems >= 2 else {
        continue
      }

      let id = bodyItem.atIndex(1)?.stringValue ?? ""
      if id.isEmpty {
        continue
      }
      let bodyHTML = bodyItem.atIndex(2)?
        .stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      bodiesByID[id] = bodyHTML
    }

    return bodiesByID
  }

  private func parseDepth(from descriptor: NSAppleEventDescriptor?) -> Int {
    guard let descriptor else {
      return -1
    }
    if let rawText = descriptor.stringValue {
      let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let value = Int(text) else {
        return -1
      }
      return value
    }
    return Int(descriptor.int32Value)
  }

  /// Parses descriptor list or singleton string into normalized string array.
  private func parseStringList(from descriptor: NSAppleEventDescriptor) -> [String] {
    var values: [String] = []
    let count = descriptor.numberOfItems
    if count > 0 {
      for index in 1...count {
        guard let value = descriptor.atIndex(index)?
          .stringValue?
          .trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
          continue
        }
        values.append(value)
      }
      return values
    }

    guard let singleValue = descriptor.stringValue?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !singleValue.isEmpty else {
      return values
    }
    values.append(singleValue)
    return values
  }
}
