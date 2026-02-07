import Foundation

extension String {
  /// Backward-compatible convenience wrapper for body plain-text conversion.
  ///
  /// The canonical implementation lives in `BodyFormatter.plainText(from:)`.
  func htmlToPlainText() -> String {
    BodyFormatter.plainText(from: self)
  }

  /// Decodes basic HTML entities used in Notes body fragments.
  ///
  /// Numeric entities are decoded first, then named entities are decoded with
  /// `&amp;` last to avoid double-decoding nested entity sequences.
  ///
  /// Replacement order is intentional. `&amp;` must run last so encoded entities
  /// like `&amp;lt;` become `&lt;` instead of double-decoding to `<`.
  func decodeBasicHTMLEntities() -> String {
    var decoded = decodeNumericHTMLEntities()
    let replacements: [(entity: String, value: String)] = [
      ("&nbsp;", " "),
      ("&lt;", "<"),
      ("&gt;", ">"),
      ("&quot;", "\""),
      ("&#39;", "'"),
      ("&amp;", "&")
    ]

    for replacement in replacements {
      decoded = decoded.replacingOccurrences(
        of: replacement.entity,
        with: replacement.value
      )
    }

    return decoded
  }

  private func decodeNumericHTMLEntities() -> String {
    guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#) else {
      return self
    }

    var decoded = self
    while true {
      let nsDecoded = decoded as NSString
      let searchRange = NSRange(location: 0, length: nsDecoded.length)
      guard let match = regex.firstMatch(in: decoded, range: searchRange) else {
        break
      }

      let scalarValue: UInt32?
      if match.range(at: 1).location != NSNotFound {
        let hex = nsDecoded.substring(with: match.range(at: 1))
        scalarValue = UInt32(hex, radix: 16)
      } else if match.range(at: 2).location != NSNotFound {
        let decimal = nsDecoded.substring(with: match.range(at: 2))
        scalarValue = UInt32(decimal, radix: 10)
      } else {
        scalarValue = nil
      }

      guard let scalarValue,
            let scalar = UnicodeScalar(scalarValue),
            let range = Range(match.range, in: decoded) else {
        break
      }

      decoded.replaceSubrange(range, with: String(scalar))
    }

    return decoded
  }
}
