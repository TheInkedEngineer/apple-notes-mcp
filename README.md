# Apple Notes MCP (Swift)

A Swift 6 Model Context Protocol (MCP) server for Apple Notes.

It runs as a stdio JSON-RPC process and exposes tools to inspect accounts/folders and list, read, create, update, move, and delete Apple Notes.

## What This Server Provides

- `list_notes`: metadata listing with search, sorting, pagination, and optional body rendering format.
- `list_accounts`: account discovery for Apple Notes account names.
- `list_folders`: recursive folder discovery with account/path metadata.
- `get_note`: full note retrieval by note ID with plain, markdown, or raw HTML body output.
- `batch_get_notes`: multi-note retrieval by IDs with partial-success output and plain/markdown/raw-html body rendering.
- `batch_delete_notes`: multi-note deletion by IDs with partial-success output (`deletedIDs`, `missingIDs`, `failed`).
- `create_folder`: deterministic folder creation with nested path support and idempotent `mkdir -p` semantics.
- `create_note`: note creation with optional folder targeting and plain/html/markdown body input.
- `update_note`: note update by ID for title/body mutations with plain/html/markdown input and configurable output format.
- `rename_folder`: folder rename by path with optional account scoping.
- `delete_folder`: folder deletion with explicit cascade-confirmation safety gate.
- `delete_note`: note deletion by note ID.
- `move_folder`: folder move to destination parent path with cycle/no-op protection.
- `move_note`: note move by note ID to a destination folder path.
- Apple Notes automation permission checks before tool execution.
- Main-actor-safe AppleScript execution (`NSAppleScript` is not thread-safe).
- AppleScript calls are wrapped with a 20-second script timeout to avoid indefinite hangs when Notes is unresponsive.
- Stable JSON payload output for MCP tool results.

## Requirements

- macOS 13+
- Swift 6 toolchain
- Access to Apple Notes app data in the current macOS user session
- An MCP client (for example Claude Code)

## Quick Start

### 1) Build

```bash
swift build -c release
```

Binary:

```bash
.build/release/apple-notes-mcp
```

### 2) Configure Claude Code

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "apple-notes": {
      "command": "/absolute/path/to/apple-notes-mcp/.build/release/apple-notes-mcp",
      "args": []
    }
  }
}
```

Restart Claude Code after updating config.

### 3) Grant macOS Automation Permission

On first tool call, macOS may prompt for automation permission.

If you do not get a prompt, or it was denied previously:

1. Open `System Settings > Privacy & Security > Automation`.
2. Find the host process that launched the MCP server.
3. Enable access to `Notes`.

Important host-process detail:

- If Claude Code runs inside iTerm, iTerm is the process that needs permission.
- If Claude Code runs from another terminal/app, that host needs permission.

## Tools

## `list_accounts`

Lists all Apple Notes account names.

Input parameters:

- none

Returns:

- JSON array of account objects:
  - `name`

Behavior notes:

- Results are sorted case-insensitively by account name.

## `list_folders`

Lists Apple Notes folders recursively.

Input parameters (optional):

- `account` (`string`): scope to one account (for example `iCloud`, `On My Mac`).

Returns:

- JSON array of folder objects:
  - `account`: owning account name
  - `path`: full folder path (`Parent/Child`)
  - `name`: leaf folder name
  - `parentPath`: parent path (empty string for top-level folders)
  - `depth`: nesting depth (`0` for top-level)

Behavior notes:

- Without `account`, folders from all accounts are returned.
- With `account`, only folders in that account are returned.
- Unknown account returns a descriptive error.
- Results are sorted case-insensitively by `account`, then `path`.

## `list_notes`

Lists note metadata. Body content is omitted by default (`body: null`) for scalability and can be requested with `includeBody=true`.

Input parameters (all optional):

- `limit` (`integer >= 0`): maximum returned notes. `0` means unlimited.
- `offset` (`integer >= 0`): skip first N matched notes. Requires `limit > 0`.
- `searchText` (`string`): non-empty trimmed text query.
- `searchIn` (`"title" | "body" | "all"`): defaults to `title` when `searchText` is set.
- `account` (`string`): optional account scope (for example `iCloud`, `On My Mac`).
- `folder` (`string`): optional nested folder path scope (for example `Jokes/IT`).
- `includeBody` (`boolean`): include body content for returned notes.
- `bodyFormat` (`"plain" | "markdown" | "html"`): body output format when `includeBody=true`. Ignored when `includeBody=false`.
- `orderBy` (`"modified" | "created"`): sort field.
- `orderDirection` (`"recent" | "oldest"`): direction for ordering.
- `createdAfter` (`string`): ISO8601 lower bound (inclusive) for creation date.
- `createdBefore` (`string`): ISO8601 upper bound (inclusive) for creation date. Date-only input is treated as end of day.
- `modifiedAfter` (`string`): ISO8601 lower bound (inclusive) for modification date.
- `modifiedBefore` (`string`): ISO8601 upper bound (inclusive) for modification date. Date-only input is treated as end of day.

Behavior notes:

- Fast-path optimization is used for simple metadata-only limit queries:
  - `limit > 0`
  - no `searchText`
  - no `orderBy`/`orderDirection`
  - `includeBody=false`
  - no `folder` scope (account-only scope is supported)
  - In this mode, AppleScript fetches only the requested metadata window (`offset` + `limit`) while returning the same metadata shape.
- Without `orderBy`, native Notes traversal order is used.
- `orderDirection=oldest` without `orderBy` traverses reverse native order internally.
- `searchIn=body` and `searchIn=all` perform batched body lookups.
- For `searchIn=all`, title matches are accepted before body lookup to reduce AppleScript calls.
- `includeBody=true` reuses bodies already fetched during body search and only fetches missing selected note IDs.
- `includeBody=true` without search fetches bodies only for the final selected notes.
- `bodyFormat="html"` returns raw stored Notes HTML (no heading stripping or conversion).
- When metadata title is empty, `list_notes` resolves title from the body heading for consistent title behavior with `get_note` and `batch_get_notes`.
- Body search always matches on plain text converted from Notes HTML, not on raw markup.
- If body lookup fails for individual notes, those notes are still returned with `body: null` (not a query error).
- Folder filtering is pushed to AppleScript metadata fetch, so the rest of the pipeline only processes in-scope notes.

Folder target formats:

- `account` omitted + `folder` provided: resolve folder path across all accounts (must be unique).
- `account` provided + `folder` omitted: list all notes in that account.
- `account` + `folder`: resolve folder path inside that account.
- `folder` supports nesting with `/` (for example `Parent/Child/Leaf`).
- Folder matching is case-sensitive.

Validation rules:

- Negative `limit` or `offset` is invalid.
- `offset` requires a positive `limit`.
- `searchIn` requires `searchText`.
- Malformed folder paths (for example `/Work`, `Work/`, `Work//Sub`) are rejected.
- Folder lookup errors are explicit (`account not found`, `folder not found`, `ambiguous folder`).

## `get_note`

Fetches one full note by ID.

Input parameters:

- `id` (required, non-empty `string`)
- `bodyFormat` (optional `"plain" | "markdown" | "html"`, defaults to `"plain"`)

Returns:

- A JSON array with one note object on success.
- MCP error result (`isError: true`) if validation fails, note is not found, or script execution fails.

## `batch_get_notes`

Fetches multiple notes by ID in one call.

Input parameters:

- `ids` (required array of non-empty strings)
- `bodyFormat` (optional `"plain" | "markdown" | "html"`, defaults to `"plain"`)

Returns:

- JSON object:
  - `notes`: array of found note payloads
  - `missingIDs`: array of IDs not found

Behavior notes:

- Partial success by design: missing IDs do not fail the whole request.
- Duplicate IDs are deduplicated by first occurrence.
- Returned notes follow input ID order after deduplication.
- IDs are processed in batches internally (default batch size 100).
- Cancellation is checked between batches.

## `batch_delete_notes`

Deletes multiple notes by ID in one call.

Input parameters:

- `ids` (required array of non-empty strings)

Returns:

- JSON object:
  - `deletedIDs`: array of resolved note IDs deleted successfully
  - `missingIDs`: array of IDs not found
  - `failed`: array of `{ id, reason }` for IDs found but not deletable

Behavior notes:

- Partial success by design: missing/failing IDs do not fail the whole request.
- Duplicate IDs are deduplicated by first occurrence.
- `deletedIDs` contains IDs resolved by Notes before deletion (consistent with `delete_note`).
- IDs are processed in batches internally (default batch size 100).
- Cancellation is checked between batches.

## `create_note`

Creates a new note and returns the created note payload.

Input parameters:

- `title` (required, non-empty `string`)
- `body` (optional `string`, defaults to empty)
- `bodyFormat` (optional `"plain" | "html" | "markdown"`, defaults to `"plain"`)
- `account` (optional `string`)
- `folder` (optional `string`)

Placement behavior:

- `account` omitted + `folder` omitted: default Notes location.
- `account` provided + `folder` omitted: default location in that account.
- `account` omitted + `folder` provided: resolve folder path across all accounts (must be unique).
- `account` + `folder`: resolve folder path inside that account.
- `folder` supports nesting with `/` (for example `Parent/Child`).

Folder matching is case-sensitive.

Body semantics:

- `bodyFormat="plain"`:
  - Input body is plain text.
  - `&`, `<`, `>` are HTML-escaped before creation.
  - Newlines are preserved (`\n`, `\r\n`, `\r` normalized to line breaks).
- `bodyFormat="markdown"`:
  - Input body is markdown.
  - Markdown is converted to Notes-friendly rich HTML before saving.
  - If you want literal markdown text stored as-is, use `bodyFormat="plain"`.
- `bodyFormat="html"`:
  - Input body is treated as rich HTML and sent to Notes as provided.
  - Use this mode to preserve headings, lists, tables, links, and inline styling.

Title storage semantics:

- `create_note` first stores the visible title as a leading rich heading block in body HTML.
- Then it sets Apple Notes metadata title (`name`) after creation to avoid duplicate title lines in body.
- When reading raw HTML (`bodyFormat="html"`), Apple may serialize that heading as style-based HTML (for example bold + font size) rather than a literal `<h1>` tag.

Error behavior:

- Malformed folder paths (for example `/Work`, `Work/`, `Work//Sub`) return validation errors.
- Ambiguous folder names across accounts return a descriptive ambiguity error.
- Missing account/folder return descriptive not-found errors.

## `create_folder`

Creates a folder path and returns the resolved folder metadata.

Input parameters:

- `folder` (required `string`, supports nested paths like `Parent/Child`)
- `account` (optional `string`, scopes creation to a specific account)

Behavior notes:

- Missing intermediate segments are created automatically (`mkdir -p` semantics).
- `alreadyExisted=true` only when every path segment already existed.
- With `account + folder`, creation is scoped to that account.
- With `folder` only:
  - the first path segment must already exist in exactly one account
  - if it exists in multiple accounts, an ambiguity error is returned
  - if it exists in no account, an explicit error asks for `account`
- There is no implicit default-account fallback for folder creation.
- Path matching is case-sensitive.

## `update_note`

Updates an existing note by ID and returns the updated note payload.

Input parameters:

- `id` (required, non-empty `string`)
- `title` (optional non-empty `string`)
- `body` (optional `string`)
- `bodyFormat` (optional `"plain" | "html" | "markdown"`, defaults to `"plain"`)
- `bodyMode` (optional `"replace" | "append" | "prepend"`, defaults to `"replace"`)
- `outputBodyFormat` (optional `"plain" | "markdown" | "html"`, defaults to `"plain"`)

Behavior notes:

- At least one mutable field must be provided (`title` and/or `body`).
- `bodyMode` is valid only when `body` is provided.
- Title/body updates are supported; relocation is out of scope for this tool.
- Use `move_note` for folder/account moves.
- On write, Notes body storage always keeps a leading H1 heading synchronized with the effective title.
- `bodyFormat="plain"` stores escaped plain text.
- `bodyFormat="markdown"` stores rendered rich text HTML from markdown input.
- `bodyFormat="html"` stores provided rich HTML as-is.
- `outputBodyFormat="html"` returns raw stored Notes HTML.
- `outputBodyFormat="plain"` and `"markdown"` strip the injected leading title heading before formatting response content.

Error behavior:

- Validation errors for missing/invalid/empty `id`, invalid format enums, and empty update requests.
- Structured not-found mapping when the note does not exist.
- Script/runtime failures surface as MCP `isError: true`.

## `delete_note`

Deletes one note by ID.

Input parameters:

- `id` (required, non-empty `string`)

Returns:

- A JSON object:
  - `id`: deleted note ID resolved by Notes before deletion
  - `deleted`: `true`

Error behavior:

- Validation errors for missing/invalid/empty `id`.
- Structured not-found mapping when the note does not exist.
- Script/runtime failures surface as MCP `isError: true`.

## `delete_folder`

Deletes one folder path.

This is always a cascading delete operation:

- The target folder and all subfolders are deleted.
- Notes inside are moved to `Recently Deleted` as notes (folder context is not preserved).
- Notes in `Recently Deleted` are permanently removed by Notes after ~30 days.

Input parameters:

- `folder` (required `string`, supports nested paths like `Parent/Child`)
- `confirmCascadeDelete` (required `boolean`, must be `true`)
- `account` (optional `string`, scopes folder resolution to a specific account)

Safety behavior:

- `confirmCascadeDelete` is required and must be literal boolean `true`.
- There is no non-cascading mode.
- Omitting the flag, passing `false`, or passing a non-boolean value returns a validation error.

Resolution behavior:

- With `account + folder`, the target path is resolved inside that account.
- With `folder` only, target path is resolved across all accounts:
  - no match: folder not found error
  - multiple matches: ambiguous folder error
- Account-only calls are invalid (`folder` is required).

System-folder protection:

- Top-level system folders like `Notes` and `Recently Deleted` cannot be deleted.

Returns:

- JSON object:
  - `account`: resolved account name
  - `path`: resolved full folder path
  - `folder`: resolved leaf folder name
- `deleted`: `true`

## `rename_folder`

Renames one folder path.

Input parameters:

- `folder` (required `string`, supports nested paths like `Parent/Child`)
- `newName` (required non-empty `string`, must not contain `/`)
- `account` (optional `string`, scopes folder resolution to a specific account)

Behavior notes:

- With `account + folder`, target path is resolved in that account.
- With `folder` only, target path is resolved across all accounts:
  - no match: folder not found error
  - multiple matches: ambiguous folder error
- If `newName` equals current leaf name, rename is a no-op (`renamed=false`).
- Top-level system folders (`Notes`, `Recently Deleted`) cannot be renamed.
- Name conflicts in the same parent path return a descriptive error.

Returns:

- JSON object:
  - `account`
  - `oldPath`
  - `newPath`
  - `name`
  - `parentPath`
  - `depth`
  - `renamed`

## `move_folder`

Moves one folder path into a destination parent folder path. Implemented as orchestration: creates destination folder tree, moves notes by ID, then deletes source.

Input parameters:

- `folder` (required `string`, source path)
- `destinationFolder` (required `string`, destination parent path — the source folder's name is appended automatically, so do not include it. To move 'Path/To/Example' into 'NewPath', use `NewPath"`, not `"NewPath/Example"`)
- `account` (optional `string`, source account scope)
- `destinationAccount` (optional `string`, destination account scope; defaults to resolved source account)

Behavior notes:

- Source and destination paths support nesting with `/` and are case-sensitive.
- If `destinationAccount` is omitted, destination resolution uses source account.
- Note IDs are preserved; folder object identity is not.
- Destination is auto-created if missing (`mkdir -p` semantics).
- Same-named folder at destination results in merge, not conflict error.
- Source folder is deleted only after all notes are successfully moved.
- Partial failures keep source undeleted and return detailed failure info.
- Cycle protection is account-aware:
  - cycle check runs only when source and destination accounts match.
  - moving into self/descendant is rejected.
- No-op protection:
  - moving to current parent in same account is rejected.
- Top-level system folders (`Notes`, `Recently Deleted`) cannot be moved.

Returns:

- JSON object:
  - `sourceAccount`
  - `sourcePath`
  - `destinationAccount`
  - `destinationPath`
  - `folder`
  - `moved`
  - `movedNoteCount`
  - `failedNoteMoves` (array of `{noteID, noteTitle, sourceFolder, destinationFolder, reason}`)
  - `createdFolders` (array of newly created folder paths)
  - `sourceDeleted`
  - `partial`

## `move_note`

Moves one note by ID to a destination folder path.

Input parameters:

- `id` (required, non-empty `string`)
- `folder` (required `string`, supports nested paths like `Parent/Child`)
- `account` (optional `string`, scopes folder resolution to a specific account)

Returns:

- JSON object:
  - `id`: note ID
  - `title`: best-effort note metadata title (can be empty)
  - `account`: destination account name
  - `path`: destination full folder path
  - `folder`: destination leaf folder name
  - `modifiedAt`: ISO8601 timestamp

Behavior notes:

- `folder` is always required.
- `account` without `folder` is rejected.
- With `account + folder`, the destination path is resolved in that account.
- With `folder` only, destination path is resolved across all accounts:
  - no match: folder not found error
  - multiple matches: ambiguous folder error
- Same-account moves use `move n to targetFolder` and preserve the original note ID and timestamps.
- Cross-account moves recreate the note at the destination (create + delete): the note gets a new ID, timestamps reset, and attachments may not transfer.
- Cross-account scoped moves (`account` + `folder`) auto-create missing destination folders.
- `title` is informational only. Treat `id`, `account`, `path`, `folder`, and `modifiedAt` as authoritative move confirmation fields.

## Breaking Change Note

Folder targeting no longer uses `AccountName/FolderName` inside the `folder` value.

Use separate parameters instead:

- `account: "iCloud", folder: "Work"`
- `folder: "Jokes/IT"` (search all accounts, must be unique)

## Output Shape

Tool responses are JSON text content.

Note payloads (`list_notes`, `get_note`, `create_note`, `update_note`) include:

- `id`
- `title`
- `body` (`null` when not requested or unavailable; plain, markdown, or raw html depending on `bodyFormat`)
- `folder`
- `createdAt` (ISO8601 with fractional seconds)
- `modifiedAt` (ISO8601 with fractional seconds)

Timestamp note:
- Payload timestamps are UTC (`Z`) ISO8601 strings. Notes.app UI may display local time.

Delete payload (`delete_note`) includes:

- `id`
- `deleted`

Delete folder payload (`delete_folder`) includes:

- `account`
- `path`
- `folder`
- `deleted`

Rename folder payload (`rename_folder`) includes:

- `account`
- `oldPath`
- `newPath`
- `name`
- `parentPath`
- `depth`
- `renamed`

Move folder payload (`move_folder`) includes:

- `sourceAccount`
- `sourcePath`
- `destinationAccount`
- `destinationPath`
- `folder`
- `moved`

Create folder payload (`create_folder`) includes:

- `account`
- `path`
- `name`
- `parentPath`
- `depth`
- `alreadyExisted`

Batch get payload (`batch_get_notes`) includes:

- `notes` (array of note payloads)
- `missingIDs` (array of string IDs not found)

Batch delete payload (`batch_delete_notes`) includes:

- `deletedIDs` (array of resolved note IDs deleted)
- `missingIDs` (array of string IDs not found)
- `failed` (array of `{ id, reason }` rows)

Move payload (`move_note`) includes:

- `id`
- `title` (best-effort; may be empty)
- `account`
- `path`
- `folder`
- `modifiedAt`

Account payload (`list_accounts`) includes:

- `name`

Folder payload (`list_folders`) includes:

- `account`
- `path`
- `name`
- `parentPath` (empty string for root folders)
- `depth` (0-based nesting level)

## Run And Test

Run full tests:

```bash
swift test
```

Run unit target only:

```bash
swift test --filter AppleNotesMCPTests
```

Run integration smoke target only:

```bash
swift test --filter AppleNotesMCPIntegrationTests
```

## Project Layout

- `Package.swift`: package and targets.
- `Sources/AppleNotesMCP/AppleNotesMCP.swift`: process entrypoint.
- `Sources/AppleNotesMCP/Server/`: lifecycle and shutdown orchestration.
- `Sources/AppleNotesMCP/Tools/`: tool contracts and implementations.
- `Sources/AppleNotesMCP/Helpers/`: AppleScript, parsing, normalization, logging, permissions.
- `Sources/AppleNotesMCP/Errors/`: centralized error namespace (`Error.*`).
- `Sources/AppleNotesMCP/Models/`: payload and app config models.
- `Tests/AppleNotesMCPTests/`: deterministic unit tests.
- `Tests/AppleNotesMCPIntegrationTests/`: MCP wiring smoke tests.

## Troubleshooting

## The process starts but "does nothing"

Expected for stdio MCP servers. The process waits for JSON-RPC messages from the client.

## No macOS permission prompt appears

- Verify the correct host app in Automation settings (Terminal, iTerm, Claude Code host process).
- Make sure the tool is actually invoked; prompts appear on tool execution, not process startup.

## "Automation permission for Apple Notes has not been granted yet"

Grant permission in Automation settings for the host process, then invoke the tool again.

## Tool call appears to hang

- AppleScript calls are wrapped in a 20-second timeout.
- If Notes is busy/unresponsive, the call should fail with a timeout-related AppleScript error instead of hanging indefinitely.

## Logs break protocol communication

Do not print diagnostics to stdout. MCP JSON-RPC uses stdout. This project logs to stderr via `Logger`.

## Developer Documentation

- `docs/DEVELOPMENT.md`: architecture, data flow, error model, extension workflow.
- `docs/TOOLS.md`: detailed tool contracts and algorithm semantics.
- `docs/TESTING.md`: suite design, seams, and how to add deterministic tests.
- `docs/RICH_TEXT.md`: Notes HTML guidance and markdown rendering behavior.

## License

MIT. See `LICENSE`.
