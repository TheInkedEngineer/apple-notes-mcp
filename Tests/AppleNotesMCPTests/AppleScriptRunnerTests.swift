import Foundation
import Testing
@testable import AppleNotesMCP

@MainActor
@Suite("AppleScript Runner")
struct AppleScriptRunnerTests {
  @Test
  func runThrowsCustomErrorWhenSourceDoesNotCompile() {
    let script = AppleScript(source: "this is not valid applescript")

    do {
      _ = try script.run()
      Issue.record("Expected compile failure")
    } catch let error as Error.AppleScript {
      switch error {
      case .custom(let info):
        #expect(!info.isEmpty)
      case .failedToCreate:
        Issue.record("Expected compile error, got failedToCreate")
      }
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test
  func runThrowsCustomErrorWhenScriptExecutionFails() {
    let script = AppleScript(source: "error \"boom\"")

    do {
      _ = try script.run()
      Issue.record("Expected runtime failure")
    } catch let error as Error.AppleScript {
      switch error {
      case .custom(let info):
        #expect(info.contains("boom"))
      case .failedToCreate:
        Issue.record("Expected runtime error, got failedToCreate")
      }
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test
  func runReturnsDescriptorForValidScript() throws {
    let script = AppleScript(source: "return \"ok\"")

    let result = try script.run()
    #expect(result.stringValue == "ok")
  }

  @Test
  func runCanExecuteSameSourceMultipleTimes() throws {
    let source = "return \"stable\""

    let firstResult = try AppleScript(source: source).run()
    let secondResult = try AppleScript(source: source).run()

    #expect(firstResult.stringValue == "stable")
    #expect(secondResult.stringValue == "stable")
  }

  @Test
  func runSupportsCustomExecutionTimeoutConfiguration() throws {
    let script = AppleScript(source: "return \"ok-timeout\"", executionTimeoutSeconds: 5)
    let result = try script.run()
    #expect(result.stringValue == "ok-timeout")
  }
}
