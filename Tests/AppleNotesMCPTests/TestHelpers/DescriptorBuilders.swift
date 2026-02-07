import Foundation

struct NoteDescriptorInput: Sendable {
  let id: String
  let title: String
  let bodyHTML: String
  let createdAt: Date?
  let modifiedAt: Date?
  let folder: String
}

struct NoteMetadataDescriptorInput: Sendable {
  let id: String
  let title: String
  let createdAt: Date?
  let modifiedAt: Date?
  let folder: String
}

struct FolderDescriptorInput: Sendable {
  let account: String
  let path: String
  let name: String
  let parentPath: String
  let depth: Int
}

enum DescriptorBuilders {
  /// Builds a 6-field note descriptor used by `get_note`.
  static func makeSingleNoteDescriptor(_ input: NoteDescriptorInput) -> NSAppleEventDescriptor {
    let note = NSAppleEventDescriptor.list()
    note.insert(NSAppleEventDescriptor(string: input.id), at: 1)
    note.insert(NSAppleEventDescriptor(string: input.title), at: 2)
    note.insert(NSAppleEventDescriptor(string: input.bodyHTML), at: 3)
    note.insert(makeDateDescriptor(input.createdAt), at: 4)
    note.insert(makeDateDescriptor(input.modifiedAt), at: 5)
    note.insert(NSAppleEventDescriptor(string: input.folder), at: 6)
    return note
  }

  /// Builds a 5-field list item descriptor used by `list_notes`.
  static func makeListItemDescriptor(_ input: NoteMetadataDescriptorInput) -> NSAppleEventDescriptor {
    let note = NSAppleEventDescriptor.list()
    note.insert(NSAppleEventDescriptor(string: input.id), at: 1)
    note.insert(NSAppleEventDescriptor(string: input.title), at: 2)
    note.insert(makeDateDescriptor(input.createdAt), at: 3)
    note.insert(makeDateDescriptor(input.modifiedAt), at: 4)
    note.insert(NSAppleEventDescriptor(string: input.folder), at: 5)
    return note
  }

  static func makeNotesDescriptor(_ notes: [NoteMetadataDescriptorInput]) -> NSAppleEventDescriptor {
    let result = NSAppleEventDescriptor.list()
    for (index, note) in notes.enumerated() {
      result.insert(makeListItemDescriptor(note), at: index + 1)
    }
    return result
  }

  private static func makeDateDescriptor(_ value: Date?) -> NSAppleEventDescriptor {
    guard let value else {
      return NSAppleEventDescriptor(string: "")
    }
    return NSAppleEventDescriptor(date: value)
  }

  static func makeAccountsDescriptor(_ names: [String]) -> NSAppleEventDescriptor {
    let result = NSAppleEventDescriptor.list()
    for (index, name) in names.enumerated() {
      result.insert(NSAppleEventDescriptor(string: name), at: index + 1)
    }
    return result
  }

  static func makeFoldersDescriptor(_ folders: [FolderDescriptorInput]) -> NSAppleEventDescriptor {
    let result = NSAppleEventDescriptor.list()
    for (index, folder) in folders.enumerated() {
      let row = NSAppleEventDescriptor.list()
      row.insert(NSAppleEventDescriptor(string: folder.account), at: 1)
      row.insert(NSAppleEventDescriptor(string: folder.path), at: 2)
      row.insert(NSAppleEventDescriptor(string: folder.name), at: 3)
      row.insert(NSAppleEventDescriptor(string: folder.parentPath), at: 4)
      row.insert(NSAppleEventDescriptor(int32: Int32(folder.depth)), at: 5)
      result.insert(row, at: index + 1)
    }
    return result
  }
}
