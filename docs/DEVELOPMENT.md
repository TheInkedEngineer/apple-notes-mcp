# Development Guide

This guide explains the server architecture, design decisions, and how to extend the codebase safely.

## Design Goals

- Keep MCP protocol handling stable and simple.
- Keep AppleScript execution safe under Swift 6 concurrency rules.
- Keep tool code deterministic and testable.
- Keep tool output contracts explicit and stable.

## Runtime Architecture

## Entry Point

- File: `Sources/AppleNotesMCP/AppleNotesMCP.swift`
- Creates:
  - `Models.AppConfig`
  - `ShutdownCoordinator`
  - `Tool.Registry.default`
  - `ServerRunner`
- Calls `runner.run()` and handles fatal process-level failures.

## Server Lifecycle

- File: `Sources/AppleNotesMCP/Server/ServerRunner.swift`
- Responsibilities:
  - Build `Server` with MCP metadata/capabilities.
  - Register `tools/list` and `tools/call` handlers.
  - Start `StdioTransport`.
  - Wait for either:
    - stdio disconnect (`waitUntilCompleted()`), or
    - shutdown signal (`SIGINT`/`SIGTERM`).
  - Stop server exactly once via `StopController` actor.

Why `StopController` exists:

- Stdio disconnect and process signal can race.
- Calling `server.stop()` twice concurrently is avoidable risk.
- `StopController` serializes stop requests and enforces at-most-once stop.

## Shutdown Handling

- File: `Sources/AppleNotesMCP/Server/ShutdownCoordinator.swift`
- Uses `DispatchSourceSignal` for `SIGINT`/`SIGTERM`.
- Exposes `wait()` suspension point for async lifecycle task.
- Uses lock-protected continuation state to coordinate signal/cancellation races.
- Has testing SPI: `simulateSignalForTesting(_:)`.

## Request Flow

A `tools/call` request follows this path:

1. `ServerRunner` method handler receives the call.
2. Delegates to `Tool.Registry.execute(tool:using:)`.
3. Registry resolves tool implementation by name.
4. Registry runs automation permission check.
5. Registry invokes `tool.execute(using:)`.
6. Registry converts non-cancellation thrown errors into MCP error results (`isError: true`).
7. Tool returns MCP text payload content.

## Module Structure

## Tools

- Files: `Sources/AppleNotesMCP/Tools/*`
- Shared contract: `Tool.Blueprint`
- Registry: `Tool.Registry`
- Implementations:
  - `Tool.BatchDeleteNotes`
  - `Tool.BatchGetNotes`
  - `Tool.CreateFolder`
  - `Tool.CreateNote`
  - `Tool.DeleteFolder`
  - `Tool.DeleteNote`
  - `Tool.MoveFolder`
  - `Tool.ListAccounts`
  - `Tool.ListFolders`
  - `Tool.ListNotes`
  - `Tool.GetNote`
  - `Tool.MoveNote`
  - `Tool.RenameFolder`
  - `Tool.UpdateNote`

`Tool.ListNotes` internal query modeling is nested for locality:

- `Tool.ListNotes.Query`
- `Tool.ListNotes.Query.SearchScope`
- `Tool.ListNotes.Query.OrderField`
- `Tool.ListNotes.Query.OrderDirection`

## Helpers

- Files: `Sources/AppleNotesMCP/Helpers/*`
- Key helpers:
  - `AppleScript` / `AppleScriptExecuting`: script execution + compile cache.
  - `FolderResolution`: shared folder path parsing used by folder-aware tools.
  - `FolderScriptErrorPrefix` / `FolderScriptErrorMapper`: shared structured mapping for folder AppleScript failures.
  - `NoteScriptErrorPrefix` / `NoteScriptErrorMapper`: shared structured mapping for note not-found AppleScript failures.
  - `BodyFormatter`: centralized conversion between Notes HTML and plain/markdown output.
  - `MarkdownToNotesHTML`: markdown AST to Notes-friendly HTML renderer for write paths.
  - `String.escapedForAppleScriptLiteral()`: shared escaping for script interpolation.
  - `SystemSettings` / `PermissionChecking`: automation permission gate.
  - `NSAppleEventDescriptor` extensions: descriptor-to-model parsing.
  - `String` extensions: core HTML entity/text normalization utilities.
  - `Date` extensions: canonical ISO8601 style.
  - `Logger`: stderr-only diagnostics.

## Models

- Files: `Sources/AppleNotesMCP/Models/*`
- `Models.AppConfig`: server metadata configuration.
- `Models.Note`: canonical note payload for tools.
- `Models.Account`: canonical account payload for `list_accounts`.
- `Models.Folder`: canonical folder payload for `list_folders`.
- `Models.BatchDeleteNotesResult`: partial-success payload for `batch_delete_notes`.
- `Models.BatchGetNotesResult`: partial-success payload for `batch_get_notes`.
- `Models.CreateFolderResult`: result payload for `create_folder`.
- `Models.RenameFolderResult`: result payload for `rename_folder`.
- `Models.MoveFolderResult`: result payload for `move_folder`.
- `Array<Models.Note>.mcpPayload()`: stable JSON encoding.

## Errors

- Folder: `Sources/AppleNotesMCP/Errors/`
- Namespace: `Error.*`
- Current domains:
  - `Error.CreateNote`
  - `Error.FolderResolution`
  - `Error.SystemSettings`
  - `Error.AppleScript`
  - `Error.ListNotesQuery`
  - `Error.ListFoldersQuery`
  - `Error.GetNote`
  - `Error.BatchDeleteNotes`
  - `Error.BatchGetNotes`
  - `Error.CreateFolder`
  - `Error.DeleteFolder`
  - `Error.DeleteNote`
  - `Error.MoveFolder`
  - `Error.MoveNote`
  - `Error.RenameFolder`
  - `Error.UpdateNote`

## Concurrency Model

## Main-Actor Requirements

- `NSAppleScript` must run on main actor.
- `NSAppleEventDescriptor` parsing is main-actor isolated and returns raw body HTML for notes.
- Permission check uses Apple Event APIs and runs on main actor.

## Sendability and Safety

- Core shared structs are `Sendable`.
- `ShutdownCoordinator` is `@unchecked Sendable` with explicit lock protection.
- Injected closures for tool seams are `@Sendable`.

## Non-Negotiable Rule

Never bypass main actor for AppleScript execution/parsing.

## AppleScript Strategy

## List vs Body Retrieval

`list_notes` intentionally uses a metadata-first strategy:

- Phase 1: fetch metadata (body excluded).
  - Fast path: for simple metadata-only limit queries (`limit > 0`, no search/order, `includeBody=false`, no folder scope), fetch only the requested metadata window (`offset` + `limit`). Account-only scope is supported.
  - Default path: fetch full metadata set.
- Phase 2: fetch bodies only when search scope requires it (`body` or `all`), and in batches.

When folder/account scoping is requested, phase 1 metadata fetch is scoped
directly in AppleScript:

- `account` only: account-scoped note listing
- `folder` only: full path resolution across all accounts (ambiguity checked)
- `account + folder`: full path resolution inside one account

Sorting/searching/pagination then operate only on the scoped note set.

This keeps metadata-only queries fast and keeps body search bounded by query options.

For metadata rows with empty titles, `list_notes` runs a targeted body lookup
for those IDs and resolves title from the leading heading. This keeps title
behavior aligned with `get_note` and `batch_get_notes`.

When `includeBody=true`, `list_notes` performs a final body attach step:

- Reuse raw HTML bodies already fetched during selection (`searchIn=body|all`).
- Fetch only missing selected note IDs in one additional batch.
- Format output to `plain`, `markdown`, or raw `html` based on query `bodyFormat`.
- Keep notes in result even if a per-note body lookup is missing (`body=nil`).

Body search semantics:

- matching runs on plain text converted from raw HTML.
- cached raw HTML is retained for later output formatting.
- this prevents search behavior from being polluted by HTML tags.
- plain-text conversion is owned by `BodyFormatter.plainText(from:)`; `String.htmlToPlainText()` is a compatibility wrapper.

## Note Creation: Body-Contains-Title Pattern

Apple Notes stores the visible title as the first heading element in the
body HTML. When creating a note via `make new note`, always use
`{name:"", body:bodyValue}` — never include the title in `name` at creation
time, or the title appears twice (once from `name`, once from the heading
in `body`).

After creation, `name` can be set separately (`set name of n to titleValue`)
for metadata sync. This is what `create_note` does in all its script paths.

Cross-account `move_note` follows the same rule: when recreating the note at
the destination, it uses `{body:originalBody}` without `name`, because the
original body HTML already contains the title heading.

`create_note` uses structured AppleScript error prefixes for robust mapping:

- `MCP_ACCOUNT_NOT_FOUND::...`
- `MCP_FOLDER_NOT_FOUND::segment::fullPath`
- `MCP_FOLDER_AMBIGUOUS::fullPath::account1||account2`

This avoids brittle parsing of localized/free-form AppleScript messages.

`list_notes` uses the same folder prefix contract, which keeps folder error
behavior consistent across tools.

`list_folders` also reuses the same folder/account prefix contract for
account resolution failures and returns folder tree data as stable path rows.

`create_folder` reuses the same folder/account prefix contract and adds
deterministic cross-account creation behavior:

- with `account`, create path segments in that account
- without `account`, resolve first path segment across accounts
- if no account can be inferred, fail with `accountRequiredForCreation`
- never fall back to an implicit default account

`rename_folder` and `move_folder` reuse the same folder/account resolution
prefix contract and add mutation-specific prefixes:

- `MCP_CANNOT_MODIFY_SYSTEM_FOLDER::...`
- `MCP_FOLDER_NAME_CONFLICT::...`
- `MCP_INVALID_MOVE_TARGET::...` (move-folder path safety)

`get_note` and `delete_note` share a note-not-found prefix contract:

- `MCP_NOTE_NOT_FOUND::...`

`get_note` supports output body formatting:

- `plain` (default)
- `markdown`
- `html` (raw Notes body HTML)

`batch_get_notes` follows the same read-format behavior as `get_note`:

- `plain` (default)
- `markdown`
- `html` (raw Notes body HTML)

and adds partial-success semantics:

- `notes`: found note payloads
- `missingIDs`: IDs not found in Notes

IDs are processed in chunks (default 100), with cancellation checkpoints between
chunk executions.

`batch_delete_notes` follows the same chunking/cancellation pattern:

- `deletedIDs`: resolved IDs deleted successfully
- `missingIDs`: IDs not found
- `failed`: per-ID deletion failures with reason text

This tool is partial-success by design and does not fail the full request for
per-ID not-found or per-ID delete failures.

`create_note` supports input body formatting:

- `plain` (default, escaped)
- `html` (rich Notes HTML as provided)
- `markdown` (converted to Notes-friendly HTML before write)

Important caller contract:

- `bodyFormat=markdown` stores rendered rich text, not literal markdown.
- use `bodyFormat=plain` when literal markdown text should be stored verbatim.

`update_note` follows the same body input formats as `create_note` and adds
body mutation modes:

- `replace`: replace logical content
- `append`: append logical content
- `prepend`: prepend logical content

`update_note` title/body writes always enforce the same stored-body policy as
`create_note`: a leading H1 heading synchronized with the effective title.

When response body format is `plain` or `markdown`, that injected heading is
stripped from output content. When format is `html`, raw stored Notes HTML is
returned unchanged.

## Script Caching

- `AppleScript` compiles and executes per invocation on the main actor.
- Each script execution is wrapped in an AppleScript `with timeout` block
  (20 seconds default) to avoid indefinite hangs when Notes is unresponsive.
- No source-based cache is used, which avoids unbounded growth when scripts include dynamic interpolated values.
- AppleScript error output is normalized into newline-delimited diagnostics (`message`, `brief`, `code`, optional `range`) while preserving structured prefix parsing on the first line.

## Build Metadata

- Server metadata uses `Models.AppConfig.default` as the single source of truth for name/version/listChanged.
- Integration tests reuse this same config constant to avoid version drift.

## Permission Model

Permission is enforced centrally in `Tool.Registry.execute(...)` before any known tool runs.

Why centralized:

- Consistent behavior across all tools.
- One place to evolve permission policy if needed.
- Tool authors do not duplicate permission boilerplate.

Unknown tools bypass permission and return an unknown-tool error immediately.

## Logging Rules

MCP JSON-RPC uses stdout. Any non-protocol stdout text corrupts client communication.

Required rule:

- Diagnostics must go to stderr only (`Logger`).

## Adding a New Tool

Use this exact workflow.

## 1) Create the Tool Type

- Add file under `Sources/AppleNotesMCP/Tools/`.
- Implement `Tool.Blueprint`:
  - `static name`
  - `static description`
  - `static inputSchema`
  - `execute(using:)`

## 2) Define Validation and Errors

- Add new error enum in `Sources/AppleNotesMCP/Errors/` using `Error.<ToolOrDomain>` naming.
- Validate and normalize input close to the tool boundary.
- Prefer typed throws where already used.

## 3) Inject External Dependencies

If logic depends on system APIs or nondeterministic behavior:

- Add injectable seams in tool initializer.
- Default to production implementations in production initializers.
- Use injected fakes/stubs in tests.

Current seam examples:

- `AppleScriptExecuting`
- `PermissionChecking`
- `bodyLookup` closure in `ListNotes`

## 4) Keep AppleScript and Parsing Boundaries Clean

- Script execution in `MainActor.run {}`.
- Parse descriptors through dedicated `NSAppleEventDescriptor` helpers.
- Keep parser output raw where needed, then apply tool-edge formatting.
- Keep output model mapping deterministic.

## 5) Register the Tool

- Update `Tool.Registry.default` in `Sources/AppleNotesMCP/Tools/Registry+Tool.swift`.
- Keep tool list deterministic and sorted behavior intact.

## 6) Add Tests Before Shipping

- Add tool-specific suite in `Tests/AppleNotesMCPTests/`.
- Cover:
  - validation failures
  - happy path
  - dependency failure propagation
  - payload contract
- Extend shared test helpers when needed.

## 7) Update Docs

For any new tool or behavior change, update:

- `README.md` (consumer-facing setup + tool usage)
- `docs/TOOLS.md` (tool contract/semantics)
- `docs/TESTING.md` (test strategy if new seams/patterns added)

## Common Pitfalls

- Running AppleScript off main actor.
- Printing debug logs to stdout.
- Forgetting to register a new tool in registry.
- Returning unstable payload fields or date formats.
- Writing tests that depend on real Notes app or real TCC state.

## Versioning Guidance

Treat these as contract changes:

- Tool name changes
- Input schema changes
- Payload shape changes
- Error message semantics relied on by clients

Update docs and release notes whenever tool contracts change.
