import Foundation
import Testing
@testable import AppleNotesMCP

@MainActor
@Suite("Descriptor Parsing")
struct DescriptorParsingTests {
  @Test
  func parseAccountsReturnsSortedInputWhenDescriptorContainsNames() {
    let descriptor = DescriptorBuilders.makeAccountsDescriptor(["iCloud", "On My Mac"])
    let parsed = descriptor.parseAccounts()

    #expect(parsed.map(\.name) == ["iCloud", "On My Mac"])
  }

  @Test
  func parseAccountsSkipsEmptyNames() {
    let descriptor = DescriptorBuilders.makeAccountsDescriptor(["iCloud", " ", "On My Mac"])
    let parsed = descriptor.parseAccounts()

    #expect(parsed.map(\.name) == ["iCloud", "On My Mac"])
  }

  @Test
  func parseFoldersParsesNestedFolderRows() {
    let descriptor = DescriptorBuilders.makeFoldersDescriptor([
      .init(account: "iCloud", path: "Work", name: "Work", parentPath: "", depth: 0),
      .init(account: "iCloud", path: "Work/Projects", name: "Projects", parentPath: "Work", depth: 1)
    ])

    let parsed = descriptor.parseFolders()
    #expect(parsed.count == 2)
    #expect(parsed[0].account == "iCloud")
    #expect(parsed[0].path == "Work")
    #expect(parsed[0].name == "Work")
    #expect(parsed[0].parentPath == "")
    #expect(parsed[0].depth == 0)
    #expect(parsed[1].path == "Work/Projects")
    #expect(parsed[1].depth == 1)
  }

  @Test
  func parseFoldersSkipsMalformedRows() {
    let badRow = NSAppleEventDescriptor.list()
    badRow.insert(NSAppleEventDescriptor(string: "iCloud"), at: 1)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(badRow, at: 1)

    let parsed = descriptor.parseFolders()
    #expect(parsed.isEmpty)
  }

  @Test
  func parseMoveResultParsesExpectedTupleShape() {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)
    descriptor.insert(NSAppleEventDescriptor(string: "Moved Title"), at: 2)
    descriptor.insert(NSAppleEventDescriptor(string: "iCloud"), at: 3)
    descriptor.insert(NSAppleEventDescriptor(string: "Work/Projects"), at: 4)
    descriptor.insert(NSAppleEventDescriptor(string: "Projects"), at: 5)
    descriptor.insert(NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 0)), at: 6)

    let parsed = descriptor.parseMoveResult()
    #expect(parsed?.id == "note-1")
    #expect(parsed?.title == "Moved Title")
    #expect(parsed?.account == "iCloud")
    #expect(parsed?.path == "Work/Projects")
    #expect(parsed?.folder == "Projects")
    #expect(parsed?.modifiedAt == "1970-01-01T00:00:00.000Z")
  }

  @Test
  func parseMoveResultReturnsNilForMalformedShape() {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)
    #expect(descriptor.parseMoveResult() == nil)
  }

  @Test
  func parseMoveResultAcceptsEmptyTitle() {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)
    descriptor.insert(NSAppleEventDescriptor(string: ""), at: 2)
    descriptor.insert(NSAppleEventDescriptor(string: "iCloud"), at: 3)
    descriptor.insert(NSAppleEventDescriptor(string: "Work"), at: 4)
    descriptor.insert(NSAppleEventDescriptor(string: "Work"), at: 5)
    descriptor.insert(NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 0)), at: 6)

    let parsed = descriptor.parseMoveResult()
    #expect(parsed?.id == "note-1")
    #expect(parsed?.title == "")
    #expect(parsed?.account == "iCloud")
  }

  @Test
  func parseBatchNoteLookupResultParsesFoundAndMissingRows() {
    let foundRows = NSAppleEventDescriptor.list()
    foundRows.insert(
      DescriptorBuilders.makeSingleNoteDescriptor(
        .init(
          id: "note-1",
          title: "First",
          bodyHTML: "<div>Body</div>",
          createdAt: Date(timeIntervalSince1970: 0),
          modifiedAt: Date(timeIntervalSince1970: 0),
          folder: "Inbox"
        )
      ),
      at: 1
    )

    let missingRows = NSAppleEventDescriptor.list()
    missingRows.insert(NSAppleEventDescriptor(string: "missing-1"), at: 1)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(foundRows, at: 1)
    descriptor.insert(missingRows, at: 2)

    let parsed = descriptor.parseBatchNoteLookupResult()
    #expect(parsed?.notes.map(\.id) == ["note-1"])
    #expect(parsed?.missingIDs == ["missing-1"])
  }

  @Test
  func parseBatchNoteLookupResultReturnsNilForMalformedShape() {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor.list(), at: 1)
    #expect(descriptor.parseBatchNoteLookupResult() == nil)
  }

  @Test
  func parseBatchDeleteResultParsesDeletedMissingAndFailedRows() {
    let deletedRows = NSAppleEventDescriptor.list()
    deletedRows.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)

    let missingRows = NSAppleEventDescriptor.list()
    missingRows.insert(NSAppleEventDescriptor(string: "missing-1"), at: 1)

    let failedRows = NSAppleEventDescriptor.list()
    let failedRow = NSAppleEventDescriptor.list()
    failedRow.insert(NSAppleEventDescriptor(string: "locked-1"), at: 1)
    failedRow.insert(NSAppleEventDescriptor(string: "Deletion denied"), at: 2)
    failedRows.insert(failedRow, at: 1)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(deletedRows, at: 1)
    descriptor.insert(missingRows, at: 2)
    descriptor.insert(failedRows, at: 3)

    let parsed = descriptor.parseBatchDeleteResult()
    #expect(parsed?.deletedIDs == ["note-1"])
    #expect(parsed?.missingIDs == ["missing-1"])
    #expect(parsed?.failed == [.init(id: "locked-1", reason: "Deletion denied")])
  }

  @Test
  func parseBatchDeleteResultReturnsNilForMalformedShape() {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor.list(), at: 1)
    #expect(descriptor.parseBatchDeleteResult() == nil)
  }

  @Test
  func parseNotesReturnsEmptyArrayForEmptyDescriptor() {
    let descriptor = NSAppleEventDescriptor.list()
    #expect(descriptor.parseNotes().isEmpty)
  }

  @Test
  func parseNotesSkipsItemsWithoutRequiredMetadataFields() {
    let noteDescriptor = NSAppleEventDescriptor.list()
    noteDescriptor.insert(NSAppleEventDescriptor(string: "id-only"), at: 1)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(noteDescriptor, at: 1)

    let parsed = descriptor.parseNotes()
    #expect(parsed.isEmpty)
  }

  @Test
  func parseNotesParsesMetadataWithoutBody() {
    let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    let secondDate = Date(timeIntervalSince1970: 1_800_000_000)

    let descriptor = DescriptorBuilders.makeNotesDescriptor([
      .init(
        id: "note-1",
        title: "First",
        createdAt: firstDate,
        modifiedAt: firstDate,
        folder: "Inbox"
      ),
      .init(
        id: "note-2",
        title: "Second",
        createdAt: secondDate,
        modifiedAt: secondDate,
        folder: "Archive"
      )
    ])

    let parsed = descriptor.parseNotes()
    #expect(parsed.count == 2)

    #expect(parsed[0].id == "note-1")
    #expect(parsed[0].title == "First")
    #expect(parsed[0].body == nil)
    #expect(parsed[0].folder == "Inbox")

    #expect(parsed[1].id == "note-2")
    #expect(parsed[1].title == "Second")
    #expect(parsed[1].body == nil)
    #expect(parsed[1].folder == "Archive")
  }

  @Test
  func parseSingleNoteParsesBodyAndMetadata() {
    let descriptor = DescriptorBuilders.makeSingleNoteDescriptor(
      .init(
        id: "single-note",
        title: "Single",
        bodyHTML: "<div>Body</div>",
        createdAt: Date(timeIntervalSince1970: 0),
        modifiedAt: Date(timeIntervalSince1970: 0),
        folder: "Work"
      )
    )

    let parsed = descriptor.parseSingleNote()
    #expect(parsed?.id == "single-note")
    #expect(parsed?.title == "Single")
    #expect(parsed?.body == "<div>Body</div>")
    #expect(parsed?.folder == "Work")
  }

  @Test
  func parseSingleNoteResolvesTitleFromLeadingHeadingWhenMetadataTitleIsEmpty() {
    let descriptor = DescriptorBuilders.makeSingleNoteDescriptor(
      .init(
        id: "single-note",
        title: "",
        bodyHTML: "<div><b><span style=\"font-size: 24px\">Heading Title</span></b></div><div><br></div><div>Body</div>",
        createdAt: Date(timeIntervalSince1970: 0),
        modifiedAt: Date(timeIntervalSince1970: 0),
        folder: "Work"
      )
    )

    let parsed = descriptor.parseSingleNote()
    #expect(parsed?.title == "Heading Title")
  }

  @Test
  func parseSingleNotePrefersMetadataTitleWhenHeadingDiffers() {
    let descriptor = DescriptorBuilders.makeSingleNoteDescriptor(
      .init(
        id: "single-note",
        title: "Metadata Title",
        bodyHTML: "<div><h1>Body Heading</h1></div><div><br></div><div>Body</div>",
        createdAt: Date(timeIntervalSince1970: 0),
        modifiedAt: Date(timeIntervalSince1970: 0),
        folder: "Work"
      )
    )

    let parsed = descriptor.parseSingleNote()
    #expect(parsed?.title == "Metadata Title")
  }

  @Test
  func parseNotesResolvesTitleFromOptionalBodyFieldWhenMetadataIsEmpty() {
    let row = NSAppleEventDescriptor.list()
    row.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)
    row.insert(NSAppleEventDescriptor(string: ""), at: 2)
    row.insert(NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 0)), at: 3)
    row.insert(NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 0)), at: 4)
    row.insert(NSAppleEventDescriptor(string: "Inbox"), at: 5)
    row.insert(
      NSAppleEventDescriptor(string: "<div><h1>Resolved Title</h1></div><div><br></div><div>Body</div>"),
      at: 6
    )

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(row, at: 1)

    let parsed = descriptor.parseNotes()
    #expect(parsed.count == 1)
    #expect(parsed[0].title == "Resolved Title")
  }

  @Test
  func parseSingleNoteReturnsNilForUnexpectedDescriptorShape() {
    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(NSAppleEventDescriptor(string: "bad"), at: 1)

    #expect(descriptor.parseSingleNote() == nil)
  }

  @Test
  func parseNoteBodiesBuildsLookupWithRawHTML() {
    let pairOne = NSAppleEventDescriptor.list()
    pairOne.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)
    pairOne.insert(NSAppleEventDescriptor(string: "<div>Hello</div>"), at: 2)

    let pairTwo = NSAppleEventDescriptor.list()
    pairTwo.insert(NSAppleEventDescriptor(string: "note-2"), at: 1)
    pairTwo.insert(NSAppleEventDescriptor(string: "<p>Tom &amp; Jerry</p>"), at: 2)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(pairOne, at: 1)
    descriptor.insert(pairTwo, at: 2)

    let bodies = descriptor.parseNoteBodies()
    #expect(bodies["note-1"] == "<div>Hello</div>")
    #expect(bodies["note-2"] == "<p>Tom &amp; Jerry</p>")
  }

  @Test
  func parseNoteBodiesTrimsLeadingAndTrailingWhitespaceInBodyHTML() {
    let pair = NSAppleEventDescriptor.list()
    pair.insert(NSAppleEventDescriptor(string: "note-1"), at: 1)
    pair.insert(NSAppleEventDescriptor(string: "  \n<div>Hello</div>\n  "), at: 2)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(pair, at: 1)

    let bodies = descriptor.parseNoteBodies()
    #expect(bodies["note-1"] == "<div>Hello</div>")
  }

  @Test
  func parseNoteBodiesSkipsMalformedRows() {
    let badPair = NSAppleEventDescriptor.list()
    badPair.insert(NSAppleEventDescriptor(string: ""), at: 1)

    let descriptor = NSAppleEventDescriptor.list()
    descriptor.insert(badPair, at: 1)

    let bodies = descriptor.parseNoteBodies()
    #expect(bodies.isEmpty)
  }

  @Test
  func parseNotesFormatsDatesUsingCanonicalISO8601Style() {
    let descriptor = DescriptorBuilders.makeNotesDescriptor([
      .init(
        id: "note-date",
        title: "Date",
        createdAt: Date(timeIntervalSince1970: 0),
        modifiedAt: Date(timeIntervalSince1970: 0),
        folder: "Inbox"
      )
    ])

    let parsed = descriptor.parseNotes()
    #expect(parsed.count == 1)

    let timestamp = parsed[0].createdAt
    #expect(timestamp == "1970-01-01T00:00:00.000Z")
    #expect(parsed[0].modifiedAt == "1970-01-01T00:00:00.000Z")
  }

  @Test
  func mcpPayloadProducesExpectedJSONStructure() throws {
    let descriptor = DescriptorBuilders.makeNotesDescriptor([
      .init(
        id: "note-json",
        title: "JSON",
        createdAt: nil,
        modifiedAt: nil,
        folder: "Work"
      )
    ])

    let notes = descriptor.parseNotes()
    let payload = try notes.mcpPayload()
    let jsonData = try #require(payload.data(using: .utf8))
    let decoded = try JSONDecoder().decode([Models.Note].self, from: jsonData)

    #expect(decoded.count == 1)
    #expect(decoded[0].id == "note-json")
    #expect(decoded[0].title == "JSON")
    #expect(decoded[0].body == nil)
    #expect(decoded[0].folder == "Work")
    #expect(decoded[0].createdAt == "")
    #expect(decoded[0].modifiedAt == "")
  }
}
