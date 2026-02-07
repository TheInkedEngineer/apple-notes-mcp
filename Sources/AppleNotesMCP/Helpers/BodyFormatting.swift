import Foundation

/// Output representation requested by read tools for note bodies.
enum BodyOutputFormat: String, Sendable {
  case plain
  case markdown
  case html
}

/// Input representation accepted by write tools for note bodies.
enum BodyInputFormat: String, Sendable {
  case plain
  case html
  case markdown
}

/// Centralized body-format conversions used by tool edges.
enum BodyFormatter {
  // Apple Notes can return title headings either as semantic `<h1>` blocks or
  // as styled `<b><span style="font-size: 24px">...</span></b>` blocks.
  private static let leadingTitleHeadingRegex = try! NSRegularExpression(
    pattern: #"(?is)^\s*(?:(<div\b[^>]*>.*?</div>)\s*)?(<div\b[^>]*>\s*(?:<h1\b[^>]*>(.*?)</h1>|<b\b[^>]*>\s*<span\b[^>]*style\s*=\s*['"][^'"]*font-size\s*:\s*24px[^'"]*['"][^>]*>(.*?)</span>\s*</b>)\s*</div>)(\s*<div\b[^>]*>\s*<br\s*/?>\s*</div>)?"#
  )

  static func formatHTML(_ html: String, as format: BodyOutputFormat) -> String {
    switch format {
    case .plain:
      return plainText(from: html)
    case .markdown:
      return htmlToMarkdown(html)
    case .html:
      return html
    }
  }

  /// Canonical plain-text conversion for Apple Notes HTML fragments.
  static func plainText(from html: String) -> String {
    convertHTMLToPlainText(html)
  }

  static func prepareForNotes(_ body: String, format: BodyInputFormat) -> String {
    switch format {
    case .plain:
      return preparePlainBodyForNotes(body)
    case .html:
      return normalizeNewlines(body)
    case .markdown:
      return MarkdownToNotesHTML.render(normalizeNewlines(body))
    }
  }

  /// Composes stored Notes HTML using a canonical leading heading for title.
  static func composeStoredBodyHTML(title: String, preparedBody: String) -> String {
    let escapedTitle = escapeHTMLText(title)
    let headingBlock = "<div><h1>\(escapedTitle)</h1></div>"
    let trimmedBody = preparedBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBody.isEmpty else {
      return headingBlock
    }
    return headingBlock + "<div><br></div>" + preparedBody
  }

  /// Formats stored body HTML for output.
  ///
  /// For `html`, raw content is returned unchanged.
  /// For `plain`/`markdown`, the injected leading title heading is removed first.
  static func formatStoredBodyForOutput(
    bodyHTML: String,
    title: String,
    as format: BodyOutputFormat
  ) -> String {
    if format == .html {
      return formatHTML(bodyHTML, as: format)
    }
    let strippedBody = stripLeadingTitleHeading(from: bodyHTML, matching: title)
    return formatHTML(strippedBody, as: format)
  }

  /// Resolves a note title from metadata first, with a body-heading fallback.
  ///
  /// Apple Notes can sometimes return an empty metadata title (`name`) for
  /// notes created through AppleScript, while still storing a visible heading
  /// inside the body HTML.
  static func resolvedTitle(metadataTitle: String, bodyHTML: String?) -> String {
    let trimmedMetadata = metadataTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedMetadata.isEmpty {
      return trimmedMetadata
    }

    guard let bodyHTML,
          let heading = leadingHeading(in: bodyHTML)?.headingText else {
      return trimmedMetadata
    }
    return heading
  }

  /// Removes a leading title heading that matches the note title.
  ///
  /// This is used to hide the injected in-note title heading from read responses
  /// and body-search matching. Supports both semantic `<h1>` and Notes-styled
  /// heading markup. Only the first heading is considered.
  static func stripLeadingTitleHeading(from html: String, matching title: String) -> String {
    let normalizedTitle = normalizeTitleComparison(title)
    guard !normalizedTitle.isEmpty else {
      return html
    }

    guard let heading = leadingHeading(in: html) else {
      return html
    }

    let normalizedHeading = normalizeTitleComparison(heading.headingText)
    guard normalizedHeading == normalizedTitle else {
      return html
    }

    if let plainLeadingText = heading.plainLeadingText,
       normalizeTitleComparison(plainLeadingText) != normalizedTitle {
      return html
    }

    let source = html as NSString
    let bodyStart = heading.strippedRange.location + heading.strippedRange.length
    let bodyRange = NSRange(location: bodyStart, length: source.length - bodyStart)
    let remaining = source.substring(with: bodyRange)
    return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func preparePlainBodyForNotes(_ plainText: String) -> String {
    let normalized = normalizeNewlines(plainText)

    let htmlEscaped = normalized
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")

    return htmlEscaped.replacingOccurrences(of: "\n", with: "<br>")
  }

  private static func escapeHTMLText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  private static func plainTextFromHeadingHTML(_ html: String) -> String {
    let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    return stripped.decodeBasicHTMLEntities()
  }

  private static func leadingHeading(in html: String) -> LeadingHeading? {
    let source = html as NSString
    let fullRange = NSRange(location: 0, length: source.length)

    guard let match = leadingTitleHeadingRegex.firstMatch(in: html, range: fullRange),
          match.range.location == 0 else {
      return nil
    }

    let headingInnerRange: NSRange
    if match.range(at: 3).location != NSNotFound {
      headingInnerRange = match.range(at: 3)
    } else if match.range(at: 4).location != NSNotFound {
      headingInnerRange = match.range(at: 4)
    } else {
      return nil
    }

    let headingInnerHTML = source.substring(with: headingInnerRange)
    let headingText = plainTextFromHeadingHTML(headingInnerHTML)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !headingText.isEmpty else {
      return nil
    }

    let plainLeadingText: String?
    if match.range(at: 1).location != NSNotFound {
      let leadingBlockHTML = source.substring(with: match.range(at: 1))
      let leadingText = plainTextFromHeadingHTML(leadingBlockHTML)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      plainLeadingText = leadingText.isEmpty ? nil : leadingText
    } else {
      plainLeadingText = nil
    }

    return LeadingHeading(
      headingText: headingText,
      plainLeadingText: plainLeadingText,
      strippedRange: match.range(at: 0)
    )
  }

  private static func normalizeTitleComparison(_ text: String) -> String {
    let normalizedWhitespace = text
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalizedWhitespace
  }

  private static func htmlToMarkdown(_ html: String) -> String {
    var text = normalizeNewlines(html)

    var tableTokens: [String: String] = [:]
    var tableIndex = 0
    text = replaceMatches(in: text, pattern: "(?is)<table\\b[^>]*>.*?</table>") { match, source in
      let tableHTML = source.substring(with: match.range)
      let token = "__MCP_TABLE_\(tableIndex)__"
      tableIndex += 1
      tableTokens[token] = markdownTableOrRawHTML(from: tableHTML)
      return token
    }

    text = replaceMatches(in: text, pattern: "(?is)<object\\b[^>]*>(.*?)</object>") { match, source in
      let innerRange = match.range(at: 1)
      let inner = innerRange.location == NSNotFound ? "" : source.substring(with: innerRange)
      if inner.contains("__MCP_TABLE_") {
        return inner
      }
      return "[Embedded Content]"
    }

    text = text.replacingOccurrences(
      of: "(?is)<img\\b[^>]*>",
      with: "[Attachment]",
      options: .regularExpression
    )

    text = replaceMatches(in: text, pattern: "(?is)<h([1-3])\\b[^>]*>(.*?)</h\\1>") { match, source in
      let levelString = source.substring(with: match.range(at: 1))
      let inner = source.substring(with: match.range(at: 2))
      let level = Int(levelString) ?? 1
      let heading = inlineMarkdown(from: inner)
      return "\n\(String(repeating: "#", count: level)) \(heading)\n\n"
    }

    text = replaceMatches(in: text, pattern: "(?is)<ol\\b[^>]*>(.*?)</ol>") { match, source in
      let inner = source.substring(with: match.range(at: 1))
      let items = listItems(from: inner, ordered: true)
      guard !items.isEmpty else {
        return ""
      }
      return "\n\(items.joined(separator: "\n"))\n\n"
    }

    text = replaceMatches(in: text, pattern: "(?is)<ul\\b[^>]*>(.*?)</ul>") { match, source in
      let inner = source.substring(with: match.range(at: 1))
      let items = listItems(from: inner, ordered: false)
      guard !items.isEmpty else {
        return ""
      }
      return "\n\(items.joined(separator: "\n"))\n\n"
    }

    text = replaceMatches(
      in: text,
      pattern: "(?is)<a\\b[^>]*href\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)')[^>]*>(.*?)</a>"
    ) { match, source in
      let url: String
      if match.range(at: 1).location != NSNotFound {
        url = source.substring(with: match.range(at: 1))
      } else if match.range(at: 2).location != NSNotFound {
        url = source.substring(with: match.range(at: 2))
      } else {
        return source.substring(with: match.range)
      }
      let inner = source.substring(with: match.range(at: 3))
      let label = inlineMarkdown(from: inner)
      guard !label.isEmpty else {
        return "<\(url)>"
      }
      return "[\(label)](\(url))"
    }

    text = applyInlineMarkdownReplacements(text, lineBreakReplacement: "\n")
    text = text.replacingOccurrences(of: "(?i)</div>", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "(?i)<div[^>]*>", with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: "(?i)<p[^>]*>", with: "", options: .regularExpression)

    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = text.decodeBasicHTMLEntities()

    text = text.replacingOccurrences(of: "__MCP_UNDERLINE_OPEN__", with: "<u>")
    text = text.replacingOccurrences(of: "__MCP_UNDERLINE_CLOSE__", with: "</u>")

    for (token, replacement) in tableTokens {
      text = text.replacingOccurrences(of: token, with: replacement)
    }

    text = normalizeMarkdownWhitespace(text)
    return text
  }

  private static func listItems(from html: String, ordered: Bool) -> [String] {
    let nsHTML = html as NSString
    let regex = try? NSRegularExpression(pattern: "(?is)<li\\b[^>]*>(.*?)</li>")
    let matches = regex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []

    var items: [String] = []
    for (index, match) in matches.enumerated() {
      let inner = nsHTML.substring(with: match.range(at: 1))
      let value = inlineMarkdown(from: inner)
      guard !value.isEmpty else {
        continue
      }
      if ordered {
        items.append("\(index + 1). \(value)")
      } else {
        items.append("- \(value)")
      }
    }

    return items
  }

  private static func inlineMarkdown(from html: String) -> String {
    var text = applyInlineMarkdownReplacements(normalizeNewlines(html), lineBreakReplacement: " ")
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = text.decodeBasicHTMLEntities()
    text = text.replacingOccurrences(of: "__MCP_UNDERLINE_OPEN__", with: "<u>")
    text = text.replacingOccurrences(of: "__MCP_UNDERLINE_CLOSE__", with: "</u>")
    text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private struct LeadingHeading: Sendable {
    let headingText: String
    let plainLeadingText: String?
    let strippedRange: NSRange
  }

  private static func applyInlineMarkdownReplacements(_ text: String, lineBreakReplacement: String) -> String {
    var updated = text
    updated = updated.replacingOccurrences(of: "(?i)<u\\b[^>]*>", with: "__MCP_UNDERLINE_OPEN__", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)</u>", with: "__MCP_UNDERLINE_CLOSE__", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)<(strong|b)\\b[^>]*>", with: "**", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)</(strong|b)>", with: "**", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)<(em|i)\\b[^>]*>", with: "*", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)</(em|i)>", with: "*", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)<(strike|s|del)\\b[^>]*>", with: "~~", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)</(strike|s|del)>", with: "~~", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)<(tt|code)\\b[^>]*>", with: "`", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)</(tt|code)>", with: "`", options: .regularExpression)
    updated = updated.replacingOccurrences(of: "(?i)<br\\s*/?>", with: lineBreakReplacement, options: .regularExpression)
    return updated
  }

  private static func markdownTableOrRawHTML(from tableHTML: String) -> String {
    let table = normalizeNewlines(tableHTML)
    let nsTable = table as NSString
    let rowRegex = try? NSRegularExpression(pattern: "(?is)<tr\\b[^>]*>(.*?)</tr>")
    let cellRegex = try? NSRegularExpression(pattern: "(?is)<t[hd]\\b[^>]*>(.*?)</t[hd]>")

    let rowMatches = rowRegex?.matches(in: table, range: NSRange(location: 0, length: nsTable.length)) ?? []
    guard !rowMatches.isEmpty else {
      return tableHTML
    }

    var rows: [[String]] = []
    for rowMatch in rowMatches {
      let rowHTML = nsTable.substring(with: rowMatch.range(at: 1))
      let nsRow = rowHTML as NSString
      let cellMatches = cellRegex?.matches(in: rowHTML, range: NSRange(location: 0, length: nsRow.length)) ?? []
      guard !cellMatches.isEmpty else {
        continue
      }

      let cells = cellMatches.map { cellMatch -> String in
        let cellHTML = nsRow.substring(with: cellMatch.range(at: 1))
        let plainCell = inlineMarkdown(from: cellHTML).replacingOccurrences(of: "|", with: "\\|")
        return plainCell
      }
      rows.append(cells)
    }

    guard let firstCount = rows.first?.count,
          firstCount > 0,
          rows.allSatisfy({ $0.count == firstCount }) else {
      return tableHTML
    }

    let header = rows[0]
    let separator = Array(repeating: "---", count: firstCount)
    var lines: [String] = []
    lines.append("| " + header.joined(separator: " | ") + " |")
    lines.append("| " + separator.joined(separator: " | ") + " |")

    if rows.count > 1 {
      for row in rows.dropFirst() {
        lines.append("| " + row.joined(separator: " | ") + " |")
      }
    }

    return "\n" + lines.joined(separator: "\n") + "\n"
  }

  private static func normalizeMarkdownWhitespace(_ text: String) -> String {
    var normalized = normalizeNewlines(text)
    normalized = normalized.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
    normalized = normalized.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizeNewlines(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func convertHTMLToPlainText(_ html: String) -> String {
    var text = html

    let breakPatterns: [(String, String)] = [
      ("(?i)<br\\s*/?>", "\n"),
      ("(?i)</div>", "\n"),
      ("(?i)<div[^>]*>", ""),
      ("(?i)</p>", "\n"),
      ("(?i)<p[^>]*>", "")
    ]

    for (pattern, replacement) in breakPatterns {
      text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = text.decodeBasicHTMLEntities()
    text = normalizeNewlines(text)
    text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func replaceMatches(
    in text: String,
    pattern: String,
    transform: (NSTextCheckingResult, NSString) -> String
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return text
    }

    let source = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
    if matches.isEmpty {
      return text
    }

    var rebuilt = ""
    var cursor = 0

    for match in matches {
      let prefixLength = match.range.location - cursor
      if prefixLength > 0 {
        let prefixRange = NSRange(location: cursor, length: prefixLength)
        rebuilt += source.substring(with: prefixRange)
      }

      rebuilt += transform(match, source)
      cursor = match.range.location + match.range.length
    }

    let tailLength = source.length - cursor
    if tailLength > 0 {
      let tailRange = NSRange(location: cursor, length: tailLength)
      rebuilt += source.substring(with: tailRange)
    }

    return rebuilt
  }
}
