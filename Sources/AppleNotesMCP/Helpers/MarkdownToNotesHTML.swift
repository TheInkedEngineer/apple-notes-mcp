import Foundation
import Markdown

/// Converts markdown input into Apple Notes-friendly HTML fragments.
///
/// The conversion intentionally targets a conservative subset that Notes renders
/// predictably. Unsupported markdown constructs degrade to readable text blocks.
enum MarkdownToNotesHTML {
  static func render(_ markdown: String) -> String {
    let document = Document(parsing: markdown)
    let renderer = Renderer()
    let blocks = renderer.renderBlocks(in: document)
    guard !blocks.isEmpty else {
      return ""
    }
    return blocks.joined(separator: "<div><br></div>")
  }
}

private struct Renderer {
  func renderBlocks(in markup: Markup) -> [String] {
    var blocks: [String] = []
    for child in markup.children {
      if let rendered = renderBlock(child), !rendered.isEmpty {
        blocks.append(rendered)
      }
    }
    return blocks
  }

  private func renderBlock(_ markup: Markup) -> String? {
    if let heading = markup as? Heading {
      let level = min(max(heading.level, 1), 3)
      let content = renderInlineChildren(in: heading)
      return "<div><h\(level)>\(content)</h\(level)></div>"
    }

    if let paragraph = markup as? Paragraph {
      let content = renderInlineChildren(in: paragraph)
      if content.isEmpty {
        return "<div><br></div>"
      }
      return "<div>\(content)</div>"
    }

    if let unorderedList = markup as? UnorderedList {
      let items = renderListItems(in: unorderedList)
      guard !items.isEmpty else {
        return nil
      }
      return "<ul>\(items)</ul>"
    }

    if let orderedList = markup as? OrderedList {
      let items = renderListItems(in: orderedList)
      guard !items.isEmpty else {
        return nil
      }
      return "<ol>\(items)</ol>"
    }

    if let blockQuote = markup as? BlockQuote {
      let content = renderInlineChildren(in: blockQuote)
      if content.isEmpty {
        return "<div>&gt;</div>"
      }
      return "<div>&gt; \(content)</div>"
    }

    if markup is ThematicBreak {
      return "<div>---</div>"
    }

    if let codeBlock = markup as? CodeBlock {
      let escaped = escapeHTML(codeBlock.code)
      let withBreaks = escaped.replacingOccurrences(of: "\n", with: "<br>")
      return "<div><code>\(withBreaks)</code></div>"
    }

    if let htmlBlock = markup as? HTMLBlock {
      let escaped = escapeHTML(htmlBlock.rawHTML)
      if escaped.isEmpty {
        return nil
      }
      return "<div>\(escaped)</div>"
    }

    let nested = renderBlocks(in: markup)
    if nested.isEmpty {
      return nil
    }
    return nested.joined(separator: "<div><br></div>")
  }

  private func renderListItems(in list: Markup) -> String {
    var items: [String] = []
    for child in list.children {
      guard let listItem = child as? ListItem else {
        continue
      }
      let rendered = renderListItem(listItem)
      if !rendered.isEmpty {
        items.append("<li>\(rendered)</li>")
      }
    }
    return items.joined()
  }

  private func renderListItem(_ listItem: ListItem) -> String {
    var segments: [String] = []

    for child in listItem.children {
      if let paragraph = child as? Paragraph {
        let text = renderInlineChildren(in: paragraph)
        if !text.isEmpty {
          segments.append(text)
        }
        continue
      }

      if let block = renderBlock(child), !block.isEmpty {
        segments.append(stripOuterDiv(block))
      }
    }

    return segments.joined(separator: "<br>")
  }

  private func renderInlineChildren(in markup: Markup) -> String {
    var segments: [String] = []
    for child in markup.children {
      let rendered = renderInline(child)
      if !rendered.isEmpty {
        segments.append(rendered)
      }
    }
    return segments.joined()
  }

  private func renderInline(_ markup: Markup) -> String {
    if let text = markup as? Text {
      return escapeHTML(text.string)
    }

    if markup is SoftBreak {
      return " "
    }

    if markup is LineBreak {
      return "<br>"
    }

    if let emphasis = markup as? Emphasis {
      return "<i>\(renderInlineChildren(in: emphasis))</i>"
    }

    if let strong = markup as? Strong {
      return "<b>\(renderInlineChildren(in: strong))</b>"
    }

    if let strikethrough = markup as? Strikethrough {
      return "<strike>\(renderInlineChildren(in: strikethrough))</strike>"
    }

    if let inlineCode = markup as? InlineCode {
      return "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    if let link = markup as? Link {
      let destination = escapeAttribute(link.destination ?? "")
      let label = renderInlineChildren(in: link)
      if label.isEmpty {
        return "<a href=\"\(destination)\">\(destination)</a>"
      }
      return "<a href=\"\(destination)\">\(label)</a>"
    }

    if let html = markup as? InlineHTML {
      return escapeHTML(html.rawHTML)
    }

    return renderInlineChildren(in: markup)
  }

  private func stripOuterDiv(_ html: String) -> String {
    let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("<div>"), trimmed.hasSuffix("</div>") else {
      return trimmed
    }
    return String(trimmed.dropFirst(5).dropLast(6))
  }

  private func escapeHTML(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  private func escapeAttribute(_ value: String) -> String {
    escapeHTML(value)
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
