import Foundation

/// Shared parser for extracting structured payloads from AppleScript error text.
enum ScriptErrorPayload {
  static func extract(after prefix: String, in message: String) -> String? {
    guard let prefixRange = message.range(of: prefix) else {
      return nil
    }

    var payload = String(message[prefixRange.upperBound...])

    let terminators = ["\n", ";", "}"]
    for terminator in terminators {
      if let range = payload.range(of: terminator) {
        payload = String(payload[..<range.lowerBound])
      }
    }

    payload = payload.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\r\n"))
    return payload.isEmpty ? nil : payload
  }
}
