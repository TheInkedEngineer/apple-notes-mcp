import Testing
@testable import AppleNotesMCP

@Suite("AppleScript String Escaping")
struct AppleScriptStringEscapingTests {
  @Test
  func escapesQuotesBackslashesTabsAndNewlines() {
    let raw = "A \"quote\"\tLine 1\r\nLine 2\\path"
    let escaped = raw.escapedForAppleScriptLiteral()

    #expect(escaped == #"A \"quote\"\tLine 1\nLine 2\\path"#)
  }

  @Test
  func buildsEscapedListLiteralForStringArrays() {
    let literal = ["A", "B\tC", "Line\r\nBreak"].appleScriptStringListLiteral()
    #expect(literal == #""A", "B\tC", "Line\nBreak""#)
  }
}
