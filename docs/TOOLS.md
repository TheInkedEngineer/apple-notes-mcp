# Tool Reference

This document is the technical contract for the currently implemented MCP tools.

## Shared Output Contract

All tools return `CallTool.Result` with `content` as text containing JSON.

Payload shape is tool-specific:

- `list_notes`, `get_note`, `create_note`, `update_note`: JSON note payloads.
- `batch_get_notes`: JSON object with `notes` + `missingIDs`.
- `batch_delete_notes`: JSON object with `deletedIDs` + `missingIDs` + `failed`.
- `list_accounts`: JSON account objects.
- `list_folders`: JSON folder objects.
- `create_folder`: JSON folder-creation result object.
- `delete_folder`: JSON folder-deletion result object.
- `rename_folder`: JSON folder-rename result object.
- `move_folder`: JSON folder-move result object.
- `delete_note`: JSON deletion-result object.
- `move_note`: JSON move-result object.

Note payload fields:

- `id: String`
- `title: String` (best-effort for move payloads; can be empty)
- `body: String?`
- `folder: String`
- `createdAt: String`
- `modifiedAt: String`

Date format uses `Date.notesTimestamp` (ISO8601 with fractional seconds).
Timestamps are emitted in UTC (`Z`).

Account payload fields:

- `name: String`

Folder payload fields:

- `account: String`
- `path: String`
- `name: String`
- `parentPath: String` (empty for top-level folders)
- `depth: Int` (0-based nesting)

Create folder payload fields:

- `account: String`
- `path: String`
- `name: String`
- `parentPath: String` (empty for top-level folders)
- `depth: Int` (0-based nesting)
- `alreadyExisted: Bool`

Rename folder payload fields:

- `account: String`
- `oldPath: String`
- `newPath: String`
- `name: String`
- `parentPath: String`
- `depth: Int`
- `renamed: Bool`

Move folder payload fields:

- `sourceAccount: String`
- `sourcePath: String`
- `destinationAccount: String`
- `destinationPath: String`
- `folder: String`
- `moved: Bool`

Batch delete payload fields:

- `deletedIDs: [String]`
- `missingIDs: [String]`
- `failed: [BatchDeleteFailure]`

Batch delete failure fields:

- `id: String`
- `reason: String`

## `list_accounts`

## Purpose

Return all Apple Notes account names.

## Input Schema

No input fields.

## Behavior

1. Execute AppleScript `name of every account`.
2. Parse flat descriptor list into `Models.Account`.
3. Sort by account name (case-insensitive).
4. Return array payload.

## Validation

No user input, so no query validation errors are expected.

## Return Contract

On success, returns JSON array:

- `name: String`

## `list_folders`

## Purpose

Return recursive folder listings as account-scoped paths.

## Input Schema

Optional fields:

- `account: String`

## Validation

- `account` must be a string when provided.
- `account` cannot be empty after trim.

Validation failures throw `Error.ListFoldersQuery`:

- `.invalidAccountType`
- `.emptyAccount`

## Behavior

1. Parse optional account scope.
2. Execute recursive AppleScript folder walk:
  - no account: walk all accounts
  - account provided: walk only that account
3. Parse folder tuple rows into `Models.Folder`.
4. Sort by `account`, then `path` (case-insensitive).
5. Return array payload.

Row shape returned by script:

- `{account, path, name, parentPath, depth}`

`path` is the authoritative field. `name`, `parentPath`, and `depth` are
derived convenience fields for clients.

## Script Error Mapping

`list_folders` reuses shared folder prefix mapping:

- `MCP_ACCOUNT_NOT_FOUND::...` -> `Error.FolderResolution.accountNotFound`

Unknown script failures propagate and are converted by registry to MCP errors.

## `list_notes`

## Purpose

Return note metadata, with optional search, ordering, and pagination.

`list_notes` is metadata-first by default. Body content is only included when
`includeBody=true`.

## Input Schema

Optional fields:

- `limit: Int`
- `offset: Int`
- `searchText: String`
- `searchIn: "title" | "body" | "all"`
- `account: String`
- `folder: String`
- `includeBody: Bool` (default `false`)
- `bodyFormat: "plain" | "markdown" | "html"` (default `plain`)
- `orderBy: "modified" | "created"`
- `orderDirection: "recent" | "oldest"`
- `createdAfter: String` (ISO8601 date lower bound, inclusive, for creation date)
- `createdBefore: String` (ISO8601 date upper bound, inclusive, for creation date)
- `modifiedAfter: String` (ISO8601 date lower bound, inclusive, for modification date)
- `modifiedBefore: String` (ISO8601 date upper bound, inclusive, for modification date)

Implementation model:

- Parsed arguments are represented by `Tool.ListNotes.Query`.
- Ordering enum is `Tool.ListNotes.Query.OrderField`.
- Direction enum is `Tool.ListNotes.Query.OrderDirection`.
- Search scope enum is `Tool.ListNotes.Query.SearchScope`.

## Validation

- `limit` must be integer and `>= 0`.
- `limit == 0` means unlimited (`nil` internally).
- `offset` must be integer and `>= 0`.
- `offset > 0` requires `limit > 0`.
- `searchText` must be string and non-empty after trim.
- `searchIn` must be valid enum value.
- `searchIn` requires `searchText`.
- `account` must be a string when provided.
- `account` cannot be empty after trim.
- `folder` must be a string when provided.
- `folder` path supports nesting (`Parent/Child`) and rejects empty segments.
- `includeBody` must be a boolean when provided.
- `bodyFormat` must be a valid enum value when provided.
- `orderBy` and `orderDirection` must be valid enum values when present.
- `createdAfter`, `createdBefore`, `modifiedAfter`, `modifiedBefore` must be strings when provided.
- Date filter values must be valid ISO8601: `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SSZ`, `YYYY-MM-DDTHH:MM:SS.sssZ`, or with timezone offset.
- Empty date filter strings are rejected.
- `createdAfter` must not be later than `createdBefore` (contradictory range).
- `modifiedAfter` must not be later than `modifiedBefore` (contradictory range).
- Date-only `*Before` values are normalized to end-of-day (`23:59:59.999Z`).
- Date-only `*After` values are normalized to start-of-day (`00:00:00.000Z`).

Validation failures throw:

- `Error.ListNotesQuery` for non-folder query fields.
- `Error.FolderResolution` for folder path validation/lookup errors.

Both are surfaced by registry as MCP error results.

## Selection Pipeline

High-level algorithm:

1. Fetch note metadata via AppleScript.
  - Fast path:
    - Used when query is metadata-only and simple:
      - `limit > 0`
      - no `searchText`
      - no `orderBy`/`orderDirection`
      - `includeBody=false`
      - no `folder` scope (account-only scope is supported)
    - In this mode only the requested metadata window is fetched (`offset` + `limit`).
  - Default path:
    - Fetch full metadata set and apply the full query pipeline in Swift.
  - If scope is provided, metadata fetch is scoped in AppleScript:
    - `account` only: list all notes from that account.
    - `folder` only: resolve full folder path across all accounts, fail on ambiguity.
    - `account + folder`: resolve full folder path inside account.
2. Apply date-range filtering (when any date filter is present):
  - Filter notes by `createdAfter`/`createdBefore` against `createdAt`.
  - Filter notes by `modifiedAfter`/`modifiedBefore` against `modifiedAt`.
  - All comparisons are inclusive (`>=` / `<=`).
  - Notes with empty timestamp strings are excluded when the corresponding date filter is present.
  - When any date filter is present, the metadata fast path is disabled (full note set is needed).
3. Build traversal order:
  - Sort by `orderBy` + direction when provided.
  - Otherwise use native order.
  - Special case: `orderDirection=oldest` without `orderBy` traverses reversed native order.
4. Apply search:
  - `title`: compare normalized title only.
  - `body`: batch body lookup and compare normalized plain text converted from raw HTML.
  - `all`: title check first, fallback to body lookup + plain-text conversion.
5. Apply `offset` against matched sequence.
6. Apply `limit` against post-offset sequence.
7. If `includeBody=true`, attach bodies to selected notes:
  - Reuse raw HTML bodies already fetched during `body`/`all` search.
  - Fetch missing selected note IDs in one additional batch.
  - Format body output according to `bodyFormat` (`plain`, `markdown`, or raw `html`).
8. Resolve missing metadata titles:
  - If metadata title is empty, perform targeted body lookups for those IDs.
  - Resolve title from leading body heading for parity with `get_note` and `batch_get_notes`.

Body lookup is batched (default batch size: 50 IDs).

Per-note body lookup failures are non-fatal. Notes remain in the response with
`body: null`.

`bodyFormat` is ignored when `includeBody=false`.

When `bodyFormat=html`, raw Notes body HTML is returned unchanged.

## Search Matching

String matching is case-insensitive and diacritic-insensitive via `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)`.

Body search never matches against raw HTML tags.

## `create_note`

## Purpose

Create a new note and return the created note payload.

## Input Schema

Required fields:

- `title: String` (trimmed, non-empty)

Optional fields:

- `body: String` (defaults to `""`)
- `bodyFormat: "plain" | "html" | "markdown"` (defaults to `plain`)
- `account: String` (optional account target)
- `folder: String` (folder target)

Folder target formats:

- `account` omitted + `folder` omitted: default Notes location.
- `account` only: default location in that account.
- `folder` only: resolve full path across all accounts; must match exactly one account.
- `account + folder`: resolve full path inside that account.
- `folder` supports nesting with `/`.

Folder matching is case-sensitive.

## Validation

Validation failures throw:

- `Error.CreateNote`:
  - `.missingTitle`
  - `.invalidTitleType`
  - `.emptyTitle`
  - `.invalidBodyType`
  - `.invalidBodyFormatType`
  - `.invalidBodyFormatValue`
  - `.invalidScriptResponse`
- `Error.FolderResolution`:
  - `.invalidAccountType`
  - `.emptyAccount`
  - `.invalidFolderType`
  - `.emptyFolder`
  - `.invalidFolderPathFormat`
  - `.folderNotFound`
  - `.ambiguousFolder`
  - `.accountNotFound`

Path format rules:

- `folder` is a path only (account is separate).
- Leading/trailing slash is invalid.
- Consecutive slashes are invalid.

## Body Semantics

`bodyFormat=plain`:

1. Normalize newlines (`\\r\\n` and `\\r` to `\\n`).
2. Escape `&`, `<`, `>`.
3. Convert `\\n` to `<br>`.

`bodyFormat=html`:

1. Keep rich HTML body as provided.
2. Escape only for safe AppleScript interpolation.

`bodyFormat=markdown`:

1. Parse markdown with `swift-markdown` AST.
2. Render Notes-friendly HTML subset (`<div>`, headings, lists, inline styles, links, code).
3. Escape generated HTML for AppleScript interpolation.
4. If literal markdown text should be stored, callers must use `bodyFormat=plain`.

Title storage behavior:

- `create_note` stores the caller-provided title as a leading heading block in note body HTML.
- After creation, it sets Notes metadata `name` to the same title so clients can rely on note metadata.
- On raw HTML reads, Apple Notes may normalize that heading to style-based markup instead of preserving a literal `<h1>` tag.

## Folder Resolution Semantics

- `folder` omitted: create in default location.
- `account` only: create in that account default location.
- `folder` only: search all accounts for full folder path.
  - no match -> `.folderNotFound`
  - more than one match -> `.ambiguousFolder`
- `account + folder`:
  - missing account -> `.accountNotFound`
  - missing path segment in account -> `.folderNotFound`

## Script Error Mapping

`create_note` uses structured AppleScript prefixes and maps them back to
typed Swift errors:

- `MCP_ACCOUNT_NOT_FOUND::...`
- `MCP_FOLDER_NOT_FOUND::segment::fullPath`
- `MCP_FOLDER_AMBIGUOUS::fullPath::account1||account2`

Unknown script failures are propagated as `Error.AppleScript`.

## Return Contract

On success, returns one note in JSON array format with the shared note schema.
If descriptor shape is invalid, throws `.invalidScriptResponse`.

## `create_folder`

## Purpose

Create a folder path in Apple Notes with idempotent `mkdir -p` behavior.

## Input Schema

Required fields:

- `folder: String` (supports nested paths like `Parent/Child`)

Optional fields:

- `account: String` (account scope)

## Validation

Validation failures throw:

- `Error.CreateFolder`:
  - `.missingFolder`
  - `.invalidScriptResponse`
- `Error.FolderResolution`:
  - `.invalidAccountType`
  - `.emptyAccount`
  - `.invalidFolderType`
  - `.emptyFolder`
  - `.invalidFolderPathFormat`

## Resolution Semantics

With `account + folder`:

1. Resolve account.
2. Create missing path segments in that account.

With `folder` only:

1. Resolve the first folder segment across all accounts.
2. If first segment exists in exactly one account, create missing trailing segments there.
3. If first segment exists in multiple accounts, throw `.ambiguousFolder`.
4. If first segment exists in no account, throw `.accountRequiredForCreation`.

This tool intentionally does not choose an implicit default account.

## Creation Semantics

- Missing intermediate segments are created automatically.
- `alreadyExisted` is `true` only if all segments already existed.
- If any segment is created, `alreadyExisted` is `false`.
- Matching is case-sensitive.

## Script Error Mapping

`create_folder` reuses shared folder prefix mapping:

- `MCP_ACCOUNT_NOT_FOUND::...` -> `Error.FolderResolution.accountNotFound`
- `MCP_FOLDER_AMBIGUOUS::...` -> `Error.FolderResolution.ambiguousFolder`
- `MCP_FOLDER_CREATE_REQUIRES_ACCOUNT::...` -> `Error.FolderResolution.accountRequiredForCreation`

Unknown script failures propagate and are converted by registry to MCP errors.

## Return Contract

On success, returns one object:

- `account`
- `path`
- `name`
- `parentPath`
- `depth`
- `alreadyExisted`

## `update_note`

## Purpose

Update an existing note by ID for title/body mutations and return the updated note.

This tool intentionally does not move notes. Use `move_note` for relocation.

## Input Schema

Required fields:

- `id: String` (non-empty after trim)

Optional fields:

- `title: String` (non-empty after trim when provided)
- `body: String`
- `bodyFormat: "plain" | "html" | "markdown"` (defaults to `plain`)
- `bodyMode: "replace" | "append" | "prepend"` (defaults to `replace`)
- `outputBodyFormat: "plain" | "markdown" | "html"` (defaults to `plain`)

## Validation

Validation failures throw `Error.UpdateNote`:

- `.missingID`
- `.invalidIDType`
- `.emptyID`
- `.noChangesRequested`
- `.invalidTitleType`
- `.emptyTitle`
- `.invalidBodyType`
- `.invalidBodyFormatType`
- `.invalidBodyFormatValue`
- `.bodyModeRequiresBody`
- `.invalidBodyModeType`
- `.invalidBodyModeValue`
- `.invalidOutputBodyFormatType`
- `.invalidOutputBodyFormatValue`
- `.noteNotFound`
- `.invalidScriptResponse`

## Behavior

1. Parse and validate input.
2. Read current note snapshot by ID.
3. Build the next stored body HTML in Swift:
  - Strip existing injected title heading when it matches the current title.
  - Resolve effective title (`title` input or current title).
  - Apply `bodyMode` when `body` is provided:
    - `replace`: replace logical body with input.
    - `append`: append prepared input after existing logical body.
    - `prepend`: prepend prepared input before existing logical body.
  - Compose stored body as leading title H1 + optional separator + logical body.
4. Execute write script for updated `name` and/or `body`.
5. Parse updated note and format response body via `outputBodyFormat`.
  - `html`: raw stored Notes HTML.
  - `plain`/`markdown`: remove injected leading title heading before formatting output.

Body input handling:

- `bodyFormat=plain`: normalize newlines, HTML-escape, convert line breaks.
- `bodyFormat=html`: use provided HTML content.
- `bodyFormat=markdown`: convert markdown AST to Notes-friendly HTML.

Important caller contract:

- `bodyFormat=markdown` stores rendered rich text, not literal markdown text.
- Use `bodyFormat=plain` to store literal markdown text verbatim.

## Script Error Mapping

`update_note` reuses structured note prefix mapping:

- `MCP_NOTE_NOT_FOUND::...` -> `Error.UpdateNote.noteNotFound`

Unknown script failures propagate and are converted by registry to MCP errors.

## Return Contract

On success, returns one note in JSON array format with the shared note schema.

## `get_note`

## Purpose

Return a single note by ID with full body content.

## Input Schema

Required fields:

- `id: String` (non-empty after trim)

Optional fields:

- `bodyFormat: "plain" | "markdown" | "html"` (defaults to `plain`)

## Validation

Validation failures throw `Error.GetNote`:

- `.missingID`
- `.invalidIDType`
- `.emptyID`
- `.invalidBodyFormatType`
- `.invalidBodyFormatValue`
- `.invalidScriptResponse`

## Behavior

1. Parse and validate `id`.
2. Build AppleScript source for this specific note ID.
3. Execute script on main actor.
4. Parse descriptor with `parseSingleNote()`.
5. Format raw HTML body to requested `bodyFormat`.
  - `html` returns raw stored Notes HTML unchanged.
6. Return one-element note array payload.

`get_note` emits structured not-found errors with `MCP_NOTE_NOT_FOUND::...` and
maps them to `Error.GetNote.noteNotFound`.

Unknown AppleScript/runtime failures propagate and registry converts them to MCP
`isError: true` results.

## `batch_get_notes`

## Purpose

Fetch multiple notes by ID in a single request and return partial success data.

## Input Schema

Required fields:

- `ids: [String]` (non-empty array, each element non-empty after trim)

Optional fields:

- `bodyFormat: "plain" | "markdown" | "html"` (defaults to `plain`)

## Validation

Validation failures throw `Error.BatchGetNotes`:

- `.missingIDs`
- `.invalidIDsType`
- `.emptyIDs`
- `.invalidIDElementType(index:)`
- `.emptyID(index:)`
- `.invalidBodyFormatType`
- `.invalidBodyFormatValue`
- `.invalidScriptResponse`

## Behavior

1. Parse IDs and deduplicate by first occurrence.
2. Process IDs in chunks (default chunk size: 100).
3. Run AppleScript per chunk to fetch `{foundRows, missingIDs}`.
4. Check cancellation before and after each chunk.
5. Merge rows by note ID and preserve input order in final output.
6. Apply output body formatting (`plain`/`markdown`).

## Return Contract

On success, returns one JSON object:

- `notes: [Note]` (found notes in input order after dedup)
- `missingIDs: [String]` (IDs not found, also input-order aligned)

Missing IDs are non-fatal by design.

## `batch_delete_notes`

## Purpose

Delete multiple notes by ID in a single request and return partial success data.

## Input Schema

Required fields:

- `ids: [String]` (non-empty array, each element non-empty after trim)

## Validation

Validation failures throw `Error.BatchDeleteNotes`:

- `.missingIDs`
- `.invalidIDsType`
- `.emptyIDs`
- `.invalidIDElementType(index:)`
- `.emptyID(index:)`
- `.invalidScriptResponse`

## Behavior

1. Parse IDs and deduplicate by first occurrence.
2. Process IDs in chunks (default chunk size: 100).
3. Run AppleScript per chunk to resolve/delete IDs and collect:
  - deleted IDs
  - missing IDs
  - failed rows with script reason text
4. Check cancellation before and after each chunk.
5. Preserve caller order for `missingIDs` and `failed` in final output.

`deletedIDs` contains script-resolved IDs captured before delete, consistent with
`delete_note`.

## Return Contract

On success, returns one JSON object:

- `deletedIDs: [String]`
- `missingIDs: [String]`
- `failed: [{ id: String, reason: String }]`

Partial success is non-fatal by design.

## `delete_note`

## Purpose

Delete a single note by ID.

## Input Schema

Required fields:

- `id: String` (non-empty after trim)

## Validation

Validation failures throw `Error.DeleteNote`:

- `.missingID`
- `.invalidIDType`
- `.emptyID`
- `.noteNotFound`
- `.invalidScriptResponse`

## Behavior

1. Parse and validate `id`.
2. Build AppleScript source for the note ID.
3. Resolve note and capture `resolvedID` before deletion.
4. Delete the note.
5. Return deletion result payload.

The script returns a scalar string (`resolvedID`), not a descriptor list.

## Return Contract

On success, returns a JSON object:

- `id: String`
- `deleted: true`

## Script Error Mapping

`delete_note` uses structured note prefixes:

- `MCP_NOTE_NOT_FOUND::...`

Mapped to `Error.DeleteNote.noteNotFound`.

## `delete_folder`

## Purpose

Delete one folder path. This operation is always cascading.

Semantics:

- target folder and all subfolders are deleted
- notes inside are moved to `Recently Deleted` as notes (folder hierarchy is not preserved)
- Notes.app permanently removes notes from `Recently Deleted` after ~30 days

## Input Schema

Required fields:

- `folder: String` (supports nested path like `Parent/Child`)
- `confirmCascadeDelete: Bool` (must be `true`)

Optional fields:

- `account: String` (account scope for folder resolution)

## Validation

Validation failures throw `Error.DeleteFolder`:

- `.missingFolder`
- `.missingConfirmCascadeDelete`
- `.invalidConfirmCascadeDeleteType`
- `.confirmCascadeDeleteMustBeTrue`
- `.cannotDeleteSystemFolder`
- `.invalidScriptResponse`

Folder/account parsing errors use `Error.FolderResolution`:

- `.invalidAccountType`
- `.emptyAccount`
- `.invalidFolderType`
- `.emptyFolder`
- `.invalidFolderPathFormat`

Important safety behavior:

- `confirmCascadeDelete` is required.
- `confirmCascadeDelete` must be literal boolean `true`.
- string values such as `"true"` are rejected.
- there is no non-cascading mode.

## Folder Resolution Semantics

- `account + folder`: resolve target path inside account.
- `folder` only: resolve across all accounts.
  - no match -> `.folderNotFound`
  - multiple matches -> `.ambiguousFolder`
- account-only calls are invalid because `folder` is required.

## Behavior

1. Validate confirmation safety gate.
2. Parse folder selection (`account` optional, `folder` required).
3. Resolve target folder path in AppleScript.
4. Block deletion of top-level system folders:
  - `Notes`
  - `Recently Deleted`
5. Delete resolved folder.
6. Return `{account, path, folder, deleted: true}`.

## Return Contract

On success, returns a JSON object:

- `account: String`
- `path: String`
- `folder: String`
- `deleted: Bool` (always `true` on success)

## Script Error Mapping

`delete_folder` uses shared folder prefix mapping:

- `MCP_ACCOUNT_NOT_FOUND::...` -> `Error.FolderResolution.accountNotFound`
- `MCP_FOLDER_NOT_FOUND::segment::fullPath` -> `Error.FolderResolution.folderNotFound`
- `MCP_FOLDER_AMBIGUOUS::fullPath::account1||account2` -> `Error.FolderResolution.ambiguousFolder`

Plus delete-folder-specific protection:

- `MCP_CANNOT_DELETE_SYSTEM_FOLDER::name` -> `Error.DeleteFolder.cannotDeleteSystemFolder`

## `rename_folder`

## Purpose

Rename one folder path while preserving its parent location.

## Input Schema

Required fields:

- `folder: String` (supports nested path like `Parent/Child`)
- `newName: String` (leaf folder name; must not contain `/`)

Optional fields:

- `account: String` (account scope for folder resolution)

## Validation

Validation failures throw `Error.RenameFolder`:

- `.missingFolder`
- `.missingNewName`
- `.invalidNewNameType`
- `.emptyNewName`
- `.invalidNewNameContainsPathSeparator`
- `.cannotModifySystemFolder`
- `.folderNameConflict`
- `.invalidScriptResponse`

Folder/account parsing errors use `Error.FolderResolution`.

## Folder Resolution Semantics

- `account + folder`: resolve target path inside account.
- `folder` only: resolve full path across all accounts.
  - no match -> `.folderNotFound`
  - multiple matches -> `.ambiguousFolder`

## Behavior

1. Resolve target folder path.
2. Reject top-level system folders (`Notes`, `Recently Deleted`).
3. If `newName` equals current leaf name, return no-op (`renamed=false`).
4. Check sibling conflict in parent.
5. Rename folder leaf.
6. Return rename result payload.

## Return Contract

On success, returns a JSON object:

- `account`
- `oldPath`
- `newPath`
- `name`
- `parentPath`
- `depth`
- `renamed`

## Script Error Mapping

`rename_folder` reuses shared folder prefix mapping for account/path resolution.

Tool-specific mappings:

- `MCP_CANNOT_MODIFY_SYSTEM_FOLDER::name` -> `Error.RenameFolder.cannotModifySystemFolder`
- `MCP_FOLDER_NAME_CONFLICT::name` -> `Error.RenameFolder.folderNameConflict`

## `move_folder`

## Purpose

Move one folder path into a destination parent folder path. Implemented as orchestration of sub-tools (`create_folder`, `list_folders`, `list_notes`, `move_note`, `delete_folder`).

## Input Schema

Required fields:

- `folder: String` (source path)
- `destinationFolder: String` (destination parent path — the source folder's name is appended automatically. To move `Path/To/Example` into `NewPath`, use `destinationFolder: "NewPath"`, not `"NewPath/Example"`)

Optional fields:

- `account: String` (source account scope)
- `destinationAccount: String` (destination account scope; defaults to source account)

## Validation

Validation failures throw `Error.MoveFolder`:

- `.missingFolder`
- `.missingDestinationFolder`
- `.invalidDestinationFolderType`
- `.emptyDestinationFolder`
- `.invalidDestinationFolderPathFormat`
- `.invalidDestinationAccountType`
- `.emptyDestinationAccount`
- `.noOpMove`
- `.invalidMoveTarget`
- `.cannotModifySystemFolder`
- `.sourceFolderNotFound`
- `.sourceFolderAmbiguous`
- `.subToolFailed`

Source folder/account parsing errors use `Error.FolderResolution`.

## Source Resolution

Source folder is discovered via `list_folders`:

1. Call `list_folders` scoped to `account` (or all accounts when omitted).
2. Find exact path match. If 0 matches: `sourceFolderNotFound`. If >1 match across accounts (when account is nil): `sourceFolderAmbiguous`.
3. Determine `sourceAccount` from matched folder.
4. Determine `destinationAccount` = override ?? sourceAccount.

## Safety Checks

Performed before folder creation:

- no-op check (first):
  - rejects moves where destination already equals source parent (same account)
- cycle check is account-aware:
  - runs only when source and destination accounts are equal
  - rejects destination equal to source, or under source subtree
- system folder protection:
  - top-level `Notes` and `Recently Deleted` folders cannot be moved

## Behavior

1. Discover source folder and subtree via `list_folders`.
2. Apply no-op/cycle/system folder checks.
3. Create destination folder tree (top-down) via `create_folder` — destination auto-created if missing (`mkdir -p` semantics).
4. Move notes folder-by-folder via `move_note` — individual failures are captured, processing continues.
5. Delete source folder via `delete_folder` — only if all notes moved successfully.
6. Return result payload.

Note IDs are preserved; folder object identity is not. Same-named folder at destination results in merge, not conflict error. Operation is non-atomic with partial-failure reporting.

## Return Contract

On success, returns a JSON object:

- `sourceAccount`
- `sourcePath`
- `destinationAccount`
- `destinationPath`
- `folder`
- `moved` — true when all notes moved and source deleted
- `movedNoteCount`
- `failedNoteMoves` — array of `{noteID, noteTitle, sourceFolder, destinationFolder, reason}`
- `createdFolders` — array of newly created folder paths
- `sourceDeleted` — true when source folder tree was deleted
- `partial` — true when some notes moved but others failed

## `move_note`

## Purpose

Move a single note by ID to a destination folder path.

## Input Schema

Required fields:

- `id: String` (non-empty after trim)
- `folder: String` (destination path; supports nesting with `/`)

Optional fields:

- `account: String` (destination account scope)

## Validation

Validation failures throw:

- `Error.MoveNote`:
  - `.missingID`
  - `.invalidIDType`
  - `.emptyID`
  - `.missingFolder`
  - `.noteNotFound`
  - `.invalidScriptResponse`
- `Error.FolderResolution`:
  - `.invalidAccountType`
  - `.emptyAccount`
  - `.invalidFolderType`
  - `.emptyFolder`
  - `.invalidFolderPathFormat`
  - `.folderNotFound`
  - `.ambiguousFolder`
  - `.accountNotFound`

## Folder Resolution Semantics

- `folder` is always required.
- `account + folder`: resolve destination path inside the provided account.
- `folder` only: resolve destination path across all accounts.
  - no match -> `.folderNotFound`
  - multiple matches -> `.ambiguousFolder`
- `account` without `folder` is rejected.

## Behavior

1. Resolve and validate note ID.
2. Resolve destination folder according to account/path mode.
3. Detect whether the note belongs to the destination account.
4. **Same-account**: move note using AppleScript `move n to targetFolder`.
   Preserves the original note ID and timestamps.
5. **Cross-account**: create a new note at the destination with
   `{body:originalBody}` (without `name`, because body HTML already contains
   the title as its first heading — setting `name` too would duplicate it),
   then delete the original. The new note gets a fresh ID, reset timestamps,
   and attachments may not transfer.
6. Return destination metadata payload.

Cross-account folder auto-creation:

- **Scoped** (`account` + `folder`): missing destination folders are
  auto-created segment by segment in the target account.
- **Unscoped** (`folder` only): the folder must already exist; no
  auto-creation is performed.

Script returns tuple:

- `{id, title, account, fullPath, folderLeaf, modifiedDate}`

## Return Contract

On success, returns a JSON object:

- `id: String`
- `title: String` (best-effort; may be empty)
- `account: String`
- `path: String`
- `folder: String`
- `modifiedAt: String` (ISO8601, UTC)

Move confirmation fields considered authoritative are: `id`, `account`,
`path`, `folder`, and `modifiedAt`.

## Markdown Rendering

When `bodyFormat=markdown`, body rendering uses `BodyFormatter` with Notes-aware
rules:

- headings -> markdown headings
- bold/italic/strike/code -> markdown inline syntax
- underline preserved as inline HTML (`<u>...</u>`)
- lists -> markdown lists
- links -> `[text](url)`
- simple rectangular tables -> markdown tables
- complex tables -> raw HTML fallback
- images/unsupported embeds -> placeholders (`[Attachment]`, `[Embedded Content]`)

## Error Surfacing Rules

- Tool throws `CancellationError`: rethrown by registry.
- Any other thrown error:
  - If `LocalizedError`, `errorDescription` is returned to client.
  - Else, `String(describing:)` fallback text is returned.

## Notes For Future Tools

When adding tools, keep the same contract style:

- Strict input validation.
- Deterministic output shape.
- Main-actor safety for AppleScript and descriptor parsing.
- Error enum under `Error.*` in `Sources/AppleNotesMCP/Errors/`.
