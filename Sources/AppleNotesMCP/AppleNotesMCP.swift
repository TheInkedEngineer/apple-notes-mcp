import Foundation

/// Process entrypoint for the Apple Notes MCP server.
@main
struct AppleNotesMCPMain {
  /// Bootstraps server dependencies and blocks until shutdown.
  static func main() async {
    let config = Models.AppConfig.default

    let shutdown = ShutdownCoordinator()
    let registry = Tool.Registry.default

    let runner = ServerRunner(
      config: config,
      registry: registry,
      shutdown: shutdown
    )

    do {
      try await runner.run()
    } catch is CancellationError {
      Logger.info("Cancelled")
    } catch {
      Logger.error("Fatal: \(error)")
      exit(1)
    }
  }
}
