import MCP

/// Owns MCP server startup, handler wiring, and process lifecycle behavior.
///
/// Lifecycle policy:
/// - Start the server over stdio.
/// - Keep serving requests until either:
///   - the stdio transport ends (client disconnect), or
///   - a termination signal is received.
/// - Shut down gracefully and deterministically.
struct ServerRunner: Sendable {
  let config: Models.AppConfig
  let registry: Tool.Registry
  let shutdown: ShutdownCoordinator
  
  /// Boots and runs the MCP server until shutdown.
  ///
  /// Decision notes:
  /// - `server.start(...)` launches the receive loop asynchronously.
  ///   We therefore explicitly await `server.waitUntilCompleted()` so the
  ///   process exits when stdio disconnects.
  /// - Signal-driven shutdown is managed by a dedicated task waiting on
  ///   `ShutdownCoordinator`.
  /// - `StopController` guards against double-stop when both shutdown paths
  ///   race (common when parent termination also closes pipes).
  func run() async throws {
    // 1) Construct the server with static metadata/capabilities.
    let server = Server(
      name: config.name,
      version: config.version,
      capabilities: .init(tools: .init(listChanged: config.listChanged))
    )
    
    // 2) Register tool discovery endpoint.
    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: registry.allTools())
    }
    
    // 3) Register tool execution endpoint.
    // Cancellation must propagate through `registry.execute(...)` so shutdown
    // can unwind instead of returning spurious tool errors.
    await server.withMethodHandler(CallTool.self) { params in
      try await registry.execute(tool: params.name, using: params)
    }
    
    // 4) Install signal observers before starting transport processing.
    shutdown.install()
    
    // 5) Start stdio transport and message loop.
    Logger.info("Starting server on stdio")
    try await server.start(transport: StdioTransport())
    let stopController = StopController()

    // 6) Signal path: wait for SIGINT/SIGTERM and request a stop.
    let signalTask = Task {
      await shutdown.wait()
      await stopController.stop(
        server: server,
        reason: "Stopping server due to shutdown signal"
      )
    }

    // 7) Transport path: wait until stdio loop ends (client disconnected).
    // This makes subprocess behavior correct for MCP clients that close pipes
    // when done.
    await server.waitUntilCompleted()

    // 8) Signal task is no longer needed once transport loop completes.
    signalTask.cancel()

    // 9) Ensure stop runs exactly once across both paths.
    await stopController.stop(server: server, reason: "Stopping server")
    Logger.info("Shutdown complete")
  }
}

/// Coordinates server shutdown so `Server.stop()` is executed at most once.
///
/// Why this exists:
/// - Two independent shutdown triggers are expected in an MCP subprocess:
///   1. OS signals (`SIGINT`, `SIGTERM`)
///   2. Transport completion (stdio pipe closes / parent process disconnects)
/// - Both can happen almost at the same time.
/// - Calling `server.stop()` concurrently from both paths can create subtle races.
///
/// This actor serializes the decision and guarantees a single stop call.
private actor StopController {
  private var hasStopped = false
  
  /// Stops the server once and logs the reason.
  ///
  /// Subsequent calls are ignored by design.
  func stop(server: Server, reason: String) async {
    guard !hasStopped else {
      return
    }
    
    hasStopped = true
    Logger.info(reason)
    await server.stop()
  }
}
