import Foundation
import Testing
@_spi(Testing) @testable import AppleNotesMCP

@Suite("Shutdown Coordinator")
struct ShutdownCoordinatorTests {
  @Test
  func waitResumesWhenSignalTriggers() async throws {
    let coordinator = ShutdownCoordinator()

    let waitTask = Task {
      await coordinator.wait()
      return true
    }

    await Task.yield()
    coordinator.simulateSignalForTesting(SIGINT)

    let resumed = try await withTimeout(seconds: 1.0) {
      await waitTask.value
    }
    #expect(resumed)
  }

  @Test
  func waitReturnsImmediatelyIfAlreadyTriggered() async throws {
    let coordinator = ShutdownCoordinator()
    coordinator.simulateSignalForTesting(SIGTERM)

    let completed = try await withTimeout(seconds: 0.25) {
      await coordinator.wait()
      return true
    }

    #expect(completed)
  }

  @Test
  func waitResumesWhenTaskIsCancelled() async throws {
    let coordinator = ShutdownCoordinator()

    let waitTask = Task {
      await coordinator.wait()
      return true
    }

    await Task.yield()
    waitTask.cancel()

    let resumed = try await withTimeout(seconds: 1.0) {
      await waitTask.value
    }

    #expect(resumed)
  }

  @Test
  func waitReturnsImmediatelyWhenCalledFromCancelledTask() async throws {
    let coordinator = ShutdownCoordinator()

    let cancelledWaitTask = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      await coordinator.wait()
      return true
    }

    let completed = try await withTimeout(seconds: 0.25) {
      await cancelledWaitTask.value
    }

    #expect(completed)
  }

  @Test
  func multipleTriggersDoNotCauseDoubleResumeOrHang() async throws {
    let coordinator = ShutdownCoordinator()

    let waitTask = Task {
      await coordinator.wait()
      return true
    }

    await Task.yield()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<20 {
        group.addTask {
          coordinator.simulateSignalForTesting(SIGTERM)
        }
      }
    }

    let completed = try await withTimeout(seconds: 1.0) {
      await waitTask.value
    }

    #expect(completed)
  }
}
