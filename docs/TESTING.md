# Testing Guide

This project uses Swift Testing (`import Testing`) with deterministic unit tests and a small integration smoke target.

## Testing Principles

- No dependency on real Notes.app data for unit tests.
- No dependency on real macOS permission prompts for unit tests.
- Keep tests deterministic through dependency injection seams.
- Prefer behavior tests over implementation-detail tests.

## Run Commands

Run all tests:

```bash
swift test
```

Run unit tests only:

```bash
swift test --filter AppleNotesMCPTests
```

Run integration smoke tests only:

```bash
swift test --filter AppleNotesMCPIntegrationTests
```

## Targets

## `AppleNotesMCPTests` (unit)

Covers pure logic and seam-driven behavior:

- `String HTML Conversion`
- `Body Formatting`
- `Markdown To Notes HTML`
- `Descriptor Parsing`
- `Tool Registry`
- `Shutdown Coordinator`
- `List Notes Tool`
- `Get Note Tool`
- `Batch Get Notes Tool`
- `Batch Delete Notes Tool`
- `Create Note Tool`
- `Create Folder Tool`
- `Rename Folder Tool`
- `Move Folder Tool`
- `Update Note Tool`
- `Delete Note Tool`
- `Move Note Tool`
- `List Accounts Tool`
- `List Folders Tool`
- `AppleScript Runner`

## `AppleNotesMCPIntegrationTests` (smoke)

Uses real MCP `Server` + `Client` with in-memory transport to validate wiring:

- `tools/list` exposes registered tools.
- `tools/call` route is active.

This target intentionally does not test real Apple Notes automation.

## Core Test Seams

- `PermissionChecking`: inject allow/deny behavior in registry tests.
- `AppleScriptExecuting`: inject fake script executors for tool tests.
- `bodyLookup` closure in `Tool.ListNotes`: isolate body fetch logic.
- `ShutdownCoordinator.simulateSignalForTesting(_:)`: deterministic signal simulation.

## Shared Test Helpers

- `Tests/AppleNotesMCPTests/TestHelpers/CallToolParameterFactory.swift`
  - Creates `CallTool.Parameters` for tool tests.
- `Tests/AppleNotesMCPTests/TestHelpers/DescriptorBuilders.swift`
  - Builds synthetic `NSAppleEventDescriptor` payloads.
  - Separates metadata descriptor input from full-note descriptor input to keep list tests explicit about body omission.
- `Tests/AppleNotesMCPTests/TestHelpers/Timeout.swift`
  - `withTimeout(...)` utility for async coordination tests.
- `Tests/TestSupport/ResultHelpers.swift`
  - Shared content extraction helpers for both test targets.

## How To Test a New Tool

When adding a new tool, create a dedicated suite in `Tests/AppleNotesMCPTests/`.

Minimum required test categories:

1. Input validation
2. Successful execution path
3. Error propagation from dependencies
4. Output payload shape

For list-like tools with optional heavy fields (like `includeBody`), also test:

- default lightweight response behavior
- heavy-field opt-in behavior
- partial field-fetch failure behavior (non-fatal per-item fallback)
- account/folder scoping behavior (validation + script error mapping + nested path cases)
- plain-vs-markdown-vs-html output behavior and ignore rules (for format flags when body is omitted)

For batch mutation tools (like `batch_delete_notes`), also test:

- partial-success bucket semantics (`deletedIDs`, `missingIDs`, `failed`)
- stable ordering after input deduplication
- chunk boundaries and cancellation checkpoints

For rich text behavior, add fixture-driven tests:

- real Notes-style HTML samples
- markdown rendering expectations
- fallback behavior for complex embeds/tables

Recommended structure:

- One suite per tool: `@Suite("<Tool Name> Tool")`.
- Short tests focused on one behavior each.
- Use injected fakes instead of real AppleScript where possible.

Assertion style guidance:

- Prefer `#expect(throws:)` when only thrown type behavior matters.
- Use explicit `do/catch` when tests need to assert specific enum payload cases or custom message content.

## Async Test Timeouts

Swift Testing does not provide built-in per-test timeouts.

For async coordination tests:

- Wrap async operations with `withTimeout(seconds:operation:)`.
- Assert timeout failures explicitly when validating hang-protection behavior.

## What Not To Test

Avoid low-value tests that mirror obvious implementation details, for example:

- Trivial property assignment initializers.
- Framework behavior already guaranteed by Apple APIs.

Prefer tests for business logic, edge-case parsing, validation contracts, and lifecycle behavior.

## Maintenance Checklist

If production code changes in these areas, update tests in the same PR:

- Tool input schema or validation rules
- Note payload shape or date formatting
- Error mapping behavior
- AppleScript parsing expectations
- Shutdown/lifecycle behavior
