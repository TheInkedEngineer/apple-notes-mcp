import Testing
@testable import AppleNotesMCP

@Suite("String HTML Conversion")
struct StringHTMLConversionTests {
  @Test(arguments: [
    ("<div>Line 1</div><div>Line 2</div>", "Line 1\nLine 2"),
    ("<div><p>Hello</p></div>", "Hello"),
    ("<br>One<br/>Two<br />Three", "One\nTwo\nThree"),
    ("<div>Line\r\n\r\n\r\nLine</div>", "Line\n\nLine")
  ])
  func convertsHTMLLineBreakPatterns(input: String, expected: String) {
    #expect(input.htmlToPlainText() == expected)
  }

  @Test
  func stripsWhitespaceOnlyHTMLToEmptyString() {
    let input = "  <div> </div><p>\n</p>  "
    #expect(input.htmlToPlainText().isEmpty)
  }

  @Test
  func decodesBasicEntitiesForPlainText() {
    let input = "Tom &amp; Jerry &lt;3 &quot;quote&quot;"
    let output = input.htmlToPlainText()

    #expect(output == "Tom & Jerry <3 \"quote\"")
  }

  @Test
  func decodesAmpersandLastToAvoidDoubleDecoding() {
    let output = "&amp;lt;".decodeBasicHTMLEntities()
    #expect(output == "&lt;")
  }

  @Test
  func decodesNumericEntities() {
    let output = "A&#39;B &#x2019; C".decodeBasicHTMLEntities()
    #expect(output == "A'B ’ C")
  }

  @Test
  func doesNotDoubleDecodeAmpEncodedNumericEntities() {
    let output = "&amp;#39;".decodeBasicHTMLEntities()
    #expect(output == "&#39;")
  }
}
