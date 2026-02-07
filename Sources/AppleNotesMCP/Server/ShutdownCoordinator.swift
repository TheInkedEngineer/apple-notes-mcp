import Dispatch
import Foundation

/// Coordinates process shutdown signals for the MCP server.
///
/// Why this type exists:
/// - `ServerRunner` needs an async suspension point (`await shutdown.wait()`)
///   that unblocks when `SIGINT` or `SIGTERM` arrives.
/// - POSIX signal handlers cannot directly interact with Swift async APIs.
/// - `DispatchSourceSignal` bridges POSIX signals into normal Swift closures,
///   where we can safely resume a continuation.
///
/// Thread-safety model:
/// - This type uses an `NSLock` to protect all mutable state.
/// - We keep exactly one pending continuation at a time.
/// - Signal delivery and task cancellation may race, so both paths clear and
///   resume the pending continuation in a lock-protected critical section.
///
/// `@unchecked Sendable` rationale:
/// - `NSLock`, `DispatchSourceSignal`, and continuation storage are not
///   statically verified by the compiler as Sendable.
/// - Access to mutable members is explicitly synchronized with `lock`.
final class ShutdownCoordinator: @unchecked Sendable {
  /// Protects access to `sources`, `continuation`, and `isTriggered`.
  private let lock = NSLock()

  /// Keeps signal sources alive for the process lifetime.
  ///
  /// `DispatchSource` objects are cancelled/deallocated when they are released.
  /// Retaining them here ensures signal handlers stay active.
  private var sources: [DispatchSourceSignal] = []

  /// Suspended waiter resumed when shutdown is triggered or task is cancelled.
  ///
  /// We intentionally support one waiter because `ServerRunner` has a single
  /// lifecycle task that waits for shutdown.
  private var continuation: CheckedContinuation<Void, Never>?

  /// Guard to ensure shutdown trigger logic runs once.
  private var isTriggered = false
  
  /// Installs SIGINT and SIGTERM observers and ignores SIGPIPE.
  ///
  /// Important: calling `signal(..., SIG_IGN)` prevents default process
  /// termination behavior so Dispatch sources can receive the signals.
  /// SIGPIPE is ignored entirely (no DispatchSource) so that client
  /// disconnects during stdout writes produce `EPIPE` errors instead of
  /// killing the process.
  func install() {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    signal(SIGPIPE, SIG_IGN)
    add(SIGINT)
    add(SIGTERM)
  }
  
  /// Suspends until shutdown is triggered or task cancellation occurs.
  ///
  /// Behavior details:
  /// - If a signal already fired (`isTriggered == true`), returns immediately.
  /// - If the waiting task is cancelled, resumes promptly via `onCancel`.
  /// - Otherwise stores a continuation and waits for either `trigger(_:)` or
  ///   cancellation to resume it.
  func wait() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        lock.lock()
        defer { lock.unlock() }
        
        if isTriggered || Task.isCancelled {
          cont.resume()
          return
        }
        continuation = cont
      }
    } onCancel: {
      cancelPendingWait()
    }
  }
  
  /// Executes the one-time shutdown transition and resumes pending waiter.
  ///
  /// This can be called from Dispatch signal handlers running on a global queue.
  /// It is safe to call multiple times; only the first call has effect.
  private func trigger(_ sig: Int32) {
    lock.lock()
    if isTriggered {
      lock.unlock()
      return
    }
    isTriggered = true
    let cont = continuation
    continuation = nil
    lock.unlock()
    
    Logger.info("Received signal \(sig), shutting down")
    cont?.resume()
  }
  
  /// Resumes and clears any pending wait continuation.
  ///
  /// Used by task cancellation to ensure no suspended waiter leaks.
  private func cancelPendingWait() {
    lock.lock()
    let cont = continuation
    continuation = nil
    lock.unlock()
    cont?.resume()
  }
  
  /// Registers one signal source and starts observing it.
  ///
  /// - Parameter sig: POSIX signal number (e.g. `SIGINT`, `SIGTERM`).
  private func add(_ sig: Int32) {
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    src.setEventHandler { [weak self] in
      self?.trigger(sig)
    }
    src.resume()
    
    lock.lock()
    sources.append(src)
    lock.unlock()
  }
}

@_spi(Testing)
extension ShutdownCoordinator {
  func simulateSignalForTesting(_ signal: Int32 = SIGTERM) {
    trigger(signal)
  }
}
