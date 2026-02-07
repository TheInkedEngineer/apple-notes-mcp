import Foundation

enum TestTimeoutError: Error, Equatable {
  case timedOut(seconds: TimeInterval)
}

func withTimeout<T: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      try await operation()
    }

    group.addTask {
      try await Task.sleep(for: .seconds(seconds))
      throw TestTimeoutError.timedOut(seconds: seconds)
    }

    guard let result = try await group.next() else {
      throw TestTimeoutError.timedOut(seconds: seconds)
    }
    group.cancelAll()
    return result
  }
}
