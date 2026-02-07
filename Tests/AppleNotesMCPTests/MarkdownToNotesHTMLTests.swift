import Testing
@testable import AppleNotesMCP

@Suite("Markdown To Notes HTML")
struct MarkdownToNotesHTMLTests {
  @Test
  func rendersHeadingsParagraphsAndLists() {
    let markdown = """
    # Title

    Intro paragraph

    - One
    - Two
    """

    let html = MarkdownToNotesHTML.render(markdown)

    #expect(html == "<div><h1>Title</h1></div><div><br></div><div>Intro paragraph</div><div><br></div><ul><li>One</li><li>Two</li></ul>")
  }

  @Test
  func rendersNestedInlineFormatting() {
    let html = MarkdownToNotesHTML.render("**bold *inner* text**")
    #expect(html.contains("<div><b>bold <i>inner</i> text</b></div>"))
  }

  @Test
  func escapesRawHTMLCharactersInText() {
    let html = MarkdownToNotesHTML.render("a < b & c > d")
    #expect(html.contains("<div>a &lt; b &amp; c &gt; d</div>"))
  }

  @Test
  func rendersLinksAndInlineCode() {
    let html = MarkdownToNotesHTML.render("[OpenAI](https://openai.com) and `code`")
    #expect(html.contains("<a href=\"https://openai.com\">OpenAI</a>"))
    #expect(html.contains("<code>code</code>"))
  }

  @Test
  func rendersNestedLists() {
    let markdown = """
    - Parent
      - Child
    """

    let html = MarkdownToNotesHTML.render(markdown)
    #expect(html.contains("<ul><li>Parent<br><ul><li>Child</li></ul></li></ul>"))
  }
}
