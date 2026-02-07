import Foundation

/// Thread-safe capture helper for recording generated script source in tests.
public final class ScriptSourceStore: @unchecked Sendable {
  private let lock = NSLock()
  private var source = ""

  public init() {}

  public func set(_ value: String) {
    lock.lock()
    source = value
    lock.unlock()
  }

  public func value() -> String {
    lock.lock()
    let current = source
    lock.unlock()
    return current
  }
}
