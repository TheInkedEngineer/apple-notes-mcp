import Testing
@testable import AppleNotesMCP

@Suite("Body Formatting")
struct BodyFormattingTests {
  @Test
  func formatsSampleNotesHTMLToMarkdown() {
    let html = """
    <div><h1>New Title</h1></div>
    <div><br></div>
    <div><h2>New Heading</h2></div>
    <div><br></div>
    <div><h3>New Subheading</h3></div>
    <div><br></div>
    <div>New body text</div>
    <div><br></div>
    <div><tt>New monostyled text</tt></div>
    <div><br></div>
    <ul>
    <li>New bullet list item</li>
    </ul>
    <div><br></div>
    <ol>
    <li>New numbered list item</li>
    </ol>
    <div><br></div>
    <div><b><i><u>New bold italic underline</u></i></b></div>
    <div><br></div>
    <div><object><table cellspacing="0" cellpadding="0" style="border-collapse: collapse; direction: ltr">
    <tbody>
    <tr><td><div>New Table C1R1</div></td><td><div>New Table C2R1</div></td></tr>
    <tr><td><div>New Table C1R2</div></td><td><div>New Table C2R2</div></td></tr>
    </tbody>
    </table></object><br></div>
    <div><br></div>
    <div><img style="max-width: 100%; max-height: 100%;" src="data:image/png;base64,abc"/><br></div>
    """

    let markdown = BodyFormatter.formatHTML(html, as: .markdown)

    #expect(markdown.contains("# New Title"))
    #expect(markdown.contains("## New Heading"))
    #expect(markdown.contains("### New Subheading"))
    #expect(markdown.contains("`New monostyled text`"))
    #expect(markdown.contains("- New bullet list item"))
    #expect(markdown.contains("1. New numbered list item"))
    #expect(markdown.contains("<u>New bold italic underline</u>"))
    #expect(markdown.contains("| New Table C1R1 | New Table C2R1 |"))
    #expect(markdown.contains("[Attachment]"))
  }

  @Test
  func keepsComplexTableAsRawHTMLWhenNotRectangular() {
    let html = """
    <table>
      <tr><td>A</td><td>B</td></tr>
      <tr><td>C</td></tr>
    </table>
    """

    let markdown = BodyFormatter.formatHTML(html, as: .markdown)
    #expect(markdown.contains("<table>"))
    #expect(markdown.contains("<tr><td>A</td><td>B</td></tr>"))
  }

  @Test
  func keepsEmbeddedObjectAsPlaceholder() {
    let html = "<div><object><custom>something</custom></object></div>"
    let markdown = BodyFormatter.formatHTML(html, as: .markdown)
    #expect(markdown.contains("[Embedded Content]"))
  }

  @Test
  func preparePlainBodyEscapesHTMLAndPreservesNewlines() {
    let prepared = BodyFormatter.prepareForNotes("Line 1\nLine 2<&>", format: .plain)
    #expect(prepared == "Line 1<br>Line 2&lt;&amp;&gt;")
  }

  @Test
  func prepareHTMLBodyLeavesRichMarkupIntact() {
    let prepared = BodyFormatter.prepareForNotes("<div><b>Hello</b></div>", format: .html)
    #expect(prepared == "<div><b>Hello</b></div>")
  }

  @Test
  func formatHTMLAsHTMLReturnsRawInputUnchanged() {
    let html = "<div><h1>Title</h1></div><div><br></div><div><b>Hello</b></div>"
    let output = BodyFormatter.formatHTML(html, as: .html)
    #expect(output == html)
  }

  @Test
  func prepareMarkdownBodyConvertsToNotesHTML() {
    let prepared = BodyFormatter.prepareForNotes("## Title\n\nBody **bold**", format: .markdown)
    #expect(prepared.contains("<div><h2>Title</h2></div>"))
    #expect(prepared.contains("<div>Body <b>bold</b></div>"))
  }

  @Test
  func stripLeadingTitleHeadingRemovesMatchingHeading() {
    let html = "<div><h1>Q1-updated</h1></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == "<div>Body</div>")
  }

  @Test
  func stripLeadingTitleHeadingKeepsBodyWhenHeadingDoesNotMatch() {
    let html = "<div><h1>Other</h1></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == html)
  }

  @Test
  func stripLeadingTitleHeadingMatchesEntityEncodedTitle() {
    let html = "<div><h1>R&amp;D &lt;Q1&gt;</h1></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "R&D <Q1>")
    #expect(stripped == "<div>Body</div>")
  }

  @Test
  func stripLeadingTitleHeadingMatchesEntityEncodedStyledHeading() {
    let html = "<div><b><span style=\"font-size: 24px\">R&amp;D &lt;Q1&gt;</span></b></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "R&D <Q1>")
    #expect(stripped == "<div>Body</div>")
  }

  @Test
  func stripLeadingTitleHeadingOnlyChecksFirstHeading() {
    let html = "<div><h1>Other</h1></div><div><h1>Q1-updated</h1></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == html)
  }

  @Test
  func stripLeadingTitleHeadingHandlesWrappedAndAttributedHeading() {
    let html = "  <div class=\"wrapper\"><h1 data-x=\"1\">Q1-updated</h1></div>\n<div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == "<div>Body</div>")
  }

  @Test
  func stripLeadingTitleHeadingHandlesNotesStyledHeading() {
    let html = "<div><b><span style=\"font-size: 24px\">Q1-updated</span></b></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == "<div>Body</div>")
  }

  @Test
  func stripLeadingTitleHeadingHandlesLeadingPlainTitlePlusStyledHeading() {
    let html = "<div>Q1-updated</div><div><b><span style=\"font-size: 24px\">Q1-updated</span></b></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == "<div>Body</div>")
  }

  @Test
  func stripLeadingTitleHeadingKeepsBodyWhenLeadingPlainTextDoesNotMatchTitle() {
    let html = "<div>Intro</div><div><b><span style=\"font-size: 24px\">Q1-updated</span></b></div><div><br></div><div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == html)
  }

  @Test
  func stripLeadingTitleHeadingReturnsOriginalWhenNoHeading() {
    let html = "<div>Body</div>"
    let stripped = BodyFormatter.stripLeadingTitleHeading(from: html, matching: "Q1-updated")
    #expect(stripped == html)
  }

  @Test
  func formatsMultibyteContentAcrossMultipleRegexReplacements() {
    let html = """
    <div><h1>😀 Title</h1></div>
    <div><br></div>
    <div><h2>Café</h2></div>
    <div><a href="https://example.com">naïve 😀</a></div>
    """

    let markdown = BodyFormatter.formatHTML(html, as: .markdown)
    #expect(markdown.contains("# 😀 Title"))
    #expect(markdown.contains("## Café"))
    #expect(markdown.contains("[naïve 😀](https://example.com)"))
  }

  @Test
  func formatsSingleQuotedAnchorLinksToMarkdown() {
    let html = "<div><a href='https://example.com'>Example</a></div>"
    let markdown = BodyFormatter.formatHTML(html, as: .markdown)
    #expect(markdown.contains("[Example](https://example.com)"))
  }
}
