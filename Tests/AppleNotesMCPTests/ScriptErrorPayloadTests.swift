import Testing
@testable import AppleNotesMCP

@Suite("Script Error Payload")
struct ScriptErrorPayloadTests {
  @Test
  func extractStopsAtNSDictionaryTerminators() {
    let info = "{NSAppleScriptErrorMessage = \"MCP_NOTE_NOT_FOUND::x-coredata://123\"; NSAppleScriptErrorNumber = -1728;}"
    let payload = ScriptErrorPayload.extract(after: NoteScriptErrorPrefix.noteNotFound, in: info)
    #expect(payload == "x-coredata://123")
  }

  @Test
  func noteMapperExtractsStructuredIDFromFormattedErrorInfo() {
    let error = Error.AppleScript.custom(
      info: "{NSAppleScriptErrorMessage = \"MCP_NOTE_NOT_FOUND::missing-id\"; NSAppleScriptErrorNumber = -1728;}"
    )

    let mapped = NoteScriptErrorMapper.noteNotFoundID(from: error)
    #expect(mapped == "missing-id")
  }

  @Test
  func noteMapperExtractsStructuredIDFromNewlineDecoratedErrorInfo() {
    let error = Error.AppleScript.custom(
      info: "MCP_NOTE_NOT_FOUND::missing-id\ncode: -1728"
    )

    let mapped = NoteScriptErrorMapper.noteNotFoundID(from: error)
    #expect(mapped == "missing-id")
  }

  @Test
  func folderMapperExtractsAmbiguousAccountsFromFormattedErrorInfo() {
    let error = Error.AppleScript.custom(
      info: "{NSAppleScriptErrorMessage = \"MCP_FOLDER_AMBIGUOUS::Work::iCloud||On My Mac\"; NSAppleScriptErrorNumber = -1728;}"
    )

    let mapped = FolderScriptErrorMapper.map(error)
    #expect(mapped == .ambiguousFolder(path: "Work", accounts: ["iCloud", "On My Mac"]))
  }

  @Test
  func folderMapperExtractsAccountRequiredForCreationFromFormattedErrorInfo() {
    let error = Error.AppleScript.custom(
      info: "{NSAppleScriptErrorMessage = \"MCP_FOLDER_CREATE_REQUIRES_ACCOUNT::Work/Projects\"; NSAppleScriptErrorNumber = -1728;}"
    )

    let mapped = FolderScriptErrorMapper.map(error)
    #expect(mapped == .accountRequiredForCreation(path: "Work/Projects"))
  }

  @Test
  func folderMutationPayloadExtractsCannotModifySystemFolder() {
    let error = Error.AppleScript.custom(
      info: "{NSAppleScriptErrorMessage = \"MCP_CANNOT_MODIFY_SYSTEM_FOLDER::Notes\"; NSAppleScriptErrorNumber = -1728;}"
    )

    let payload = FolderMutationScriptErrorPayload.cannotModifySystemFolder(from: error)
    #expect(payload == "Notes")
  }

  @Test
  func folderMutationPayloadExtractsInvalidMoveTarget() {
    let error = Error.AppleScript.custom(
      info: "MCP_INVALID_MOVE_TARGET::Destination cannot be the source folder or any of its descendants."
    )

    let payload = FolderMutationScriptErrorPayload.invalidMoveTarget(from: error)
    #expect(payload == "Destination cannot be the source folder or any of its descendants.")
  }

  @Test
  func extractTrimsQuotedPayloadWithoutTruncatingOnOpeningQuote() {
    let info = "MCP_NOTE_NOT_FOUND::\"x-coredata://abc-123\"; code: -1728"
    let payload = ScriptErrorPayload.extract(after: NoteScriptErrorPrefix.noteNotFound, in: info)
    #expect(payload == "x-coredata://abc-123")
  }
}
