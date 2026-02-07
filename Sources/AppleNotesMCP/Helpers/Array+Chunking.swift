import Foundation

extension Array where Element == String {
  /// Splits string arrays into fixed-size batches while preserving order.
  ///
  /// Used by batch note tools to process IDs in deterministic chunks.
  func chunked(into size: Int) -> [[String]] {
    guard !isEmpty else {
      return []
    }

    var result: [[String]] = []
    result.reserveCapacity((count + size - 1) / size)

    var start = 0
    while start < count {
      let end = Swift.min(start + size, count)
      result.append(Array(self[start..<end]))
      start = end
    }

    return result
  }
}
