import Foundation

enum PayloadEncoding {
  static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  static func encodeToJSONString<Value: Encodable>(_ value: Value, fallback: String) throws -> String {
    let data = try makeEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? fallback
  }
}
