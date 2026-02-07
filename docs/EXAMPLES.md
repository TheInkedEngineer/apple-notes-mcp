# Tool Usage Guide with Examples

Practical usage guide for all 14 Apple Notes MCP tools. Each section shows purpose, parameters, example request/response JSON, and important limitations.

For the formal contract reference, see [TOOLS.md](TOOLS.md). For setup and configuration, see the [README](../README.md).

All examples use the MCP `tools/call` JSON-RPC format. Responses are the `content[0].text` JSON string parsed for readability.

---

## Table of Contents

1. [Account & Folder Discovery](#account--folder-discovery)
   - [list_accounts](#list_accounts)
   - [list_folders](#list_folders)
2. [Note Reading](#note-reading)
   - [list_notes](#list_notes)
   - [get_note](#get_note)
   - [batch_get_notes](#batch_get_notes)
3. [Note Writing](#note-writing)
   - [create_note](#create_note)
   - [update_note](#update_note)
4. [Note Deletion](#note-deletion)
   - [delete_note](#delete_note)
   - [batch_delete_notes](#batch_delete_notes)
5. [Note Movement](#note-movement)
   - [move_note](#move_note)
6. [Folder Management](#folder-management)
   - [create_folder](#create_folder)
   - [rename_folder](#rename_folder)
   - [move_folder](#move_folder)
   - [delete_folder](#delete_folder)
7. [Common Workflows](#common-workflows)

---

## Account & Folder Discovery

### `list_accounts`

**Purpose:** Return all Apple Notes account names.

#### Parameters

No parameters.

#### Example request

```json
{
  "name": "list_accounts",
  "arguments": {}
}
```

#### Example response

```json
[
  { "name": "iCloud" },
  { "name": "On My Mac" }
]
```

#### Limitations / notes

- Account names are **case-sensitive** everywhere in this server. `"icloud"` will not match `"iCloud"`.
- Results are sorted case-insensitively by name.

---

### `list_folders`

**Purpose:** Return recursive folder listings as account-scoped paths.

#### Parameters

| Parameter | Type   | Required | Description                      |
|-----------|--------|----------|----------------------------------|
| `account` | string | No       | Scope to one account (e.g. `"iCloud"`) |

#### Example request — all accounts

```json
{
  "name": "list_folders",
  "arguments": {}
}
```

#### Example response

```json
[
  {
    "account": "iCloud",
    "path": "Notes",
    "name": "Notes",
    "parentPath": "",
    "depth": 0
  },
  {
    "account": "iCloud",
    "path": "Work",
    "name": "Work",
    "parentPath": "",
    "depth": 0
  },
  {
    "account": "iCloud",
    "path": "Work/Projects",
    "name": "Projects",
    "parentPath": "Work",
    "depth": 1
  },
  {
    "account": "On My Mac",
    "path": "Notes",
    "name": "Notes",
    "parentPath": "",
    "depth": 0
  }
]
```

#### Example request — scoped to one account

```json
{
  "name": "list_folders",
  "arguments": {
    "account": "iCloud"
  }
}
```

#### Limitations / notes

- Results are sorted by `account` then `path` (case-insensitive).
- `path` is the authoritative field. `name`, `parentPath`, and `depth` are derived convenience fields.
- Unknown account names return an error.

---

## Note Reading

### `list_notes`

**Purpose:** Return note metadata with optional search, ordering, pagination, and body content.

#### Parameters

| Parameter        | Type    | Required | Description                                                                 |
|------------------|---------|----------|-----------------------------------------------------------------------------|
| `limit`          | integer | No       | Max notes returned. `0` = unlimited.                                        |
| `offset`         | integer | No       | Skip first N matches. Requires `limit > 0`.                                |
| `searchText`     | string  | No       | Text query (non-empty after trim).                                          |
| `searchIn`       | string  | No       | `"title"`, `"body"`, or `"all"`. Requires `searchText`. Defaults to `"title"`. |
| `account`        | string  | No       | Account scope (e.g. `"iCloud"`).                                            |
| `folder`         | string  | No       | Folder path scope (e.g. `"Work/Projects"`).                                 |
| `includeBody`    | boolean | No       | Include body content. Default `false`.                                      |
| `bodyFormat`     | string  | No       | `"plain"`, `"markdown"`, or `"html"`. Default `"plain"`. Ignored when `includeBody=false`. |
| `orderBy`        | string  | No       | `"modified"` or `"created"`.                                                |
| `orderDirection` | string  | No       | `"recent"` or `"oldest"`.                                                   |
| `createdAfter`   | string  | No       | ISO8601 lower bound (inclusive) for creation date.                           |
| `createdBefore`  | string  | No       | ISO8601 upper bound (inclusive) for creation date. Date-only = end of day.   |
| `modifiedAfter`  | string  | No       | ISO8601 lower bound (inclusive) for modification date.                       |
| `modifiedBefore` | string  | No       | ISO8601 upper bound (inclusive) for modification date. Date-only = end of day.|

#### Example request — minimal (first 5 notes)

```json
{
  "name": "list_notes",
  "arguments": {
    "limit": 5
  }
}
```

#### Example response

```json
[
  {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "title": "Meeting Notes",
    "body": null,
    "folder": "Work",
    "createdAt": "2025-01-15T09:30:00.000Z",
    "modifiedAt": "2025-01-15T14:22:10.500Z"
  },
  {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p102",
    "title": "Shopping List",
    "body": null,
    "folder": "Notes",
    "createdAt": "2025-01-14T08:00:00.000Z",
    "modifiedAt": "2025-01-14T20:15:30.000Z"
  }
]
```

#### Example request — search by title

```json
{
  "name": "list_notes",
  "arguments": {
    "searchText": "meeting",
    "searchIn": "title"
  }
}
```

#### Example request — search body text in a specific folder

```json
{
  "name": "list_notes",
  "arguments": {
    "searchText": "deadline",
    "searchIn": "body",
    "account": "iCloud",
    "folder": "Work/Projects"
  }
}
```

#### Example request — paginated

```json
{
  "name": "list_notes",
  "arguments": {
    "limit": 10,
    "offset": 20,
    "orderBy": "modified",
    "orderDirection": "recent"
  }
}
```

#### Example request — date-range filtering (notes created in January 2025)

```json
{
  "name": "list_notes",
  "arguments": {
    "createdAfter": "2025-01-01",
    "createdBefore": "2025-01-31"
  }
}
```

Date-only values are normalized automatically: `createdAfter: "2025-01-01"` becomes start of day (`2025-01-01T00:00:00.000Z`), and `createdBefore: "2025-01-31"` becomes end of day (`2025-01-31T23:59:59.999Z`).

Full ISO8601 timestamps are also accepted: `"2025-01-15T09:30:00Z"`, `"2025-01-15T09:30:00.000Z"`, or with timezone offset `"2025-01-15T09:30:00+02:00"`.

#### Example request — with body content

```json
{
  "name": "list_notes",
  "arguments": {
    "limit": 3,
    "includeBody": true,
    "bodyFormat": "markdown"
  }
}
```

#### Example response (with body)

```json
[
  {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "title": "Meeting Notes",
    "body": "## Action Items\n\n- Follow up with design team\n- Review Q1 budget",
    "folder": "Work",
    "createdAt": "2025-01-15T09:30:00.000Z",
    "modifiedAt": "2025-01-15T14:22:10.500Z"
  }
]
```

#### Limitations / notes

- `offset` requires `limit > 0`. Using `offset` with `limit: 0` is invalid.
- `searchIn` requires `searchText`. Providing `searchIn` alone is rejected.
- Body search matches **plain text** converted from Notes HTML, not raw HTML tags.
- Notes with empty titles have their title resolved from the leading body heading.
- `bodyFormat` is ignored when `includeBody` is `false` (the default).
- If body lookup fails for individual notes, those notes are still returned with `body: null`.
- Folder matching is case-sensitive.
- Date filters accept ISO8601 formats: `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SSZ`, `YYYY-MM-DDTHH:MM:SS.sssZ`, or with timezone offset.
- Notes with empty timestamps are excluded when the corresponding date filter is active.
- Contradictory ranges (`createdAfter` later than `createdBefore`) are rejected.

---

### `get_note`

**Purpose:** Return a single note by ID with full body content.

#### Parameters

| Parameter    | Type   | Required | Description                                                  |
|--------------|--------|----------|--------------------------------------------------------------|
| `id`         | string | Yes      | Note ID (e.g. `"x-coredata://..."`).                        |
| `bodyFormat` | string | No       | `"plain"`, `"markdown"`, or `"html"`. Default `"plain"`.     |

#### Example request — plain text body

```json
{
  "name": "get_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101"
  }
}
```

#### Example response

```json
[
  {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "title": "Meeting Notes",
    "body": "Action Items\n\n- Follow up with design team\n- Review Q1 budget",
    "folder": "Work",
    "createdAt": "2025-01-15T09:30:00.000Z",
    "modifiedAt": "2025-01-15T14:22:10.500Z"
  }
]
```

#### Example request — markdown body

```json
{
  "name": "get_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "bodyFormat": "markdown"
  }
}
```

#### Example request — raw HTML body

```json
{
  "name": "get_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "bodyFormat": "html"
  }
}
```

#### Limitations / notes

- Returns an **array with a single element**, not a bare object.
- `bodyFormat="html"` returns raw stored Notes HTML unchanged, including the title heading.
- `bodyFormat="plain"` and `"markdown"` strip the injected leading title heading before formatting.

---

### `batch_get_notes`

**Purpose:** Fetch multiple notes by ID in a single request with partial-success semantics.

#### Parameters

| Parameter    | Type     | Required | Description                                                  |
|--------------|----------|----------|--------------------------------------------------------------|
| `ids`        | string[] | Yes      | Array of note IDs.                                           |
| `bodyFormat` | string   | No       | `"plain"`, `"markdown"`, or `"html"`. Default `"plain"`.     |

#### Example request

```json
{
  "name": "batch_get_notes",
  "arguments": {
    "ids": [
      "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
      "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p102",
      "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p999"
    ],
    "bodyFormat": "plain"
  }
}
```

#### Example response

```json
{
  "notes": [
    {
      "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
      "title": "Meeting Notes",
      "body": "Action Items\n\n- Follow up with design team\n- Review Q1 budget",
      "folder": "Work",
      "createdAt": "2025-01-15T09:30:00.000Z",
      "modifiedAt": "2025-01-15T14:22:10.500Z"
    },
    {
      "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p102",
      "title": "Shopping List",
      "body": "Eggs\nMilk\nBread",
      "folder": "Notes",
      "createdAt": "2025-01-14T08:00:00.000Z",
      "modifiedAt": "2025-01-14T20:15:30.000Z"
    }
  ],
  "missingIDs": [
    "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p999"
  ]
}
```

#### Limitations / notes

- **Partial success by design.** Missing IDs do not fail the whole request — they appear in `missingIDs`.
- Duplicate IDs are deduplicated by first occurrence.
- Returned notes follow input ID order after deduplication.
- IDs are processed internally in chunks of ~100.

---

## Note Writing

### `create_note`

**Purpose:** Create a new note and return the created note payload.

#### Parameters

| Parameter    | Type   | Required | Description                                                  |
|--------------|--------|----------|--------------------------------------------------------------|
| `title`      | string | Yes      | Note title (non-empty after trim).                           |
| `body`       | string | No       | Note body content. Defaults to empty.                        |
| `bodyFormat` | string | No       | `"plain"`, `"html"`, or `"markdown"`. Default `"plain"`.     |
| `account`    | string | No       | Target account.                                              |
| `folder`     | string | No       | Target folder path (e.g. `"Work/Projects"`).                 |

#### Example request — plain text

```json
{
  "name": "create_note",
  "arguments": {
    "title": "Daily Standup",
    "body": "Discussed sprint priorities.\nBlocked on API review."
  }
}
```

#### Example response

```json
[
  {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p200",
    "title": "Daily Standup",
    "body": null,
    "folder": "Notes",
    "createdAt": "2025-01-16T10:00:00.000Z",
    "modifiedAt": "2025-01-16T10:00:00.000Z"
  }
]
```

#### Example request — markdown body

```json
{
  "name": "create_note",
  "arguments": {
    "title": "Project Plan",
    "body": "## Phase 1\n\n- Design review\n- **Prototype** by Friday\n\n## Phase 2\n\n1. User testing\n2. Launch prep",
    "bodyFormat": "markdown"
  }
}
```

#### Example request — HTML body

```json
{
  "name": "create_note",
  "arguments": {
    "title": "Formatted Note",
    "body": "<h2>Overview</h2><ul><li>Item one</li><li>Item two</li></ul>",
    "bodyFormat": "html"
  }
}
```

#### Example request — into a specific folder and account

```json
{
  "name": "create_note",
  "arguments": {
    "title": "Sprint Retro",
    "body": "What went well: deployment automation.",
    "account": "iCloud",
    "folder": "Work/Projects"
  }
}
```

#### Limitations / notes

- `bodyFormat="markdown"` converts markdown to **rich HTML** before storing. The note will display as rich text in Notes.app, not as literal markdown. Use `bodyFormat="plain"` to store literal markdown text.
- The title is stored as a leading heading in the body HTML, then the Notes metadata `name` is set separately. On raw HTML reads, Apple may serialize the heading as style-based markup rather than a literal `<h1>` tag.
- Response `body` is `null` because the response uses the default output format and body is only included when explicitly requested via `get_note` or `list_notes` with `includeBody`.
- Folder path must already exist (unless account-scoped, where it must also already exist). This tool does not auto-create folders — use `create_folder` first.
- Folder matching is case-sensitive.

---

### `update_note`

**Purpose:** Update an existing note's title and/or body content.

#### Parameters

| Parameter          | Type   | Required | Description                                                          |
|--------------------|--------|----------|----------------------------------------------------------------------|
| `id`               | string | Yes      | Note ID.                                                             |
| `title`            | string | No       | New title (non-empty after trim).                                    |
| `body`             | string | No       | New body content.                                                    |
| `bodyFormat`       | string | No       | `"plain"`, `"html"`, or `"markdown"`. Default `"plain"`.             |
| `bodyMode`         | string | No       | `"replace"`, `"append"`, or `"prepend"`. Default `"replace"`.        |
| `outputBodyFormat` | string | No       | `"plain"`, `"markdown"`, or `"html"`. Default `"plain"`.             |

At least one of `title` or `body` must be provided.

#### Example request — append to body

```json
{
  "name": "update_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "body": "\n\nUpdate: design review completed.",
    "bodyMode": "append"
  }
}
```

#### Example response

```json
[
  {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "title": "Meeting Notes",
    "body": "Action Items\n\n- Follow up with design team\n- Review Q1 budget\n\nUpdate: design review completed.",
    "folder": "Work",
    "createdAt": "2025-01-15T09:30:00.000Z",
    "modifiedAt": "2025-01-16T11:05:00.000Z"
  }
]
```

#### Example request — rename only

```json
{
  "name": "update_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "title": "Q1 Meeting Notes"
  }
}
```

#### Example request — replace body with markdown, get HTML output

```json
{
  "name": "update_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "body": "## Summary\n\nAll action items resolved.",
    "bodyFormat": "markdown",
    "outputBodyFormat": "html"
  }
}
```

#### Limitations / notes

- `bodyMode` requires `body` to be provided. Setting `bodyMode` without `body` is rejected.
- This tool **does not move notes**. Use `move_note` for relocation.
- `bodyFormat="markdown"` stores rendered rich HTML, not literal markdown text.
- `outputBodyFormat="html"` returns the raw stored Notes HTML. `"plain"` and `"markdown"` strip the injected leading title heading before formatting.

---

## Note Deletion

### `delete_note`

**Purpose:** Delete a single note by ID.

#### Parameters

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| `id`      | string | Yes      | Note ID.    |

#### Example request

```json
{
  "name": "delete_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p200"
  }
}
```

#### Example response

```json
{
  "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p200",
  "deleted": true
}
```

#### Limitations / notes

- The note is moved to **Recently Deleted** in Notes.app, not permanently erased. Notes.app permanently removes it after ~30 days.
- The `id` in the response is the ID resolved by Notes before deletion.

---

### `batch_delete_notes`

**Purpose:** Delete multiple notes by ID in a single request with partial-success semantics.

#### Parameters

| Parameter | Type     | Required | Description           |
|-----------|----------|----------|-----------------------|
| `ids`     | string[] | Yes      | Array of note IDs.    |

#### Example request

```json
{
  "name": "batch_delete_notes",
  "arguments": {
    "ids": [
      "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
      "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p999",
      "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p102"
    ]
  }
}
```

#### Example response

```json
{
  "deletedIDs": [
    "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p102"
  ],
  "missingIDs": [
    "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p999"
  ],
  "failed": []
}
```

#### Limitations / notes

- **Partial success by design.** Per-ID failures do not fail the whole request.
- Missing IDs appear in `missingIDs`. IDs that were found but could not be deleted appear in `failed` with a `reason`.
- Duplicate IDs are deduplicated by first occurrence.
- Notes are moved to Recently Deleted, not permanently erased.

---

## Note Movement

### `move_note`

**Purpose:** Move a single note by ID to a destination folder.

#### Parameters

| Parameter | Type   | Required | Description                                           |
|-----------|--------|----------|-------------------------------------------------------|
| `id`      | string | Yes      | Note ID.                                              |
| `folder`  | string | Yes      | Destination folder path (e.g. `"Work/Archive"`).      |
| `account` | string | No       | Destination account scope.                            |

#### Example request — same-account move

```json
{
  "name": "move_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "folder": "Work/Archive"
  }
}
```

#### Example response

```json
{
  "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
  "title": "Meeting Notes",
  "account": "iCloud",
  "path": "Work/Archive",
  "folder": "Archive",
  "modifiedAt": "2025-01-16T12:00:00.000Z"
}
```

#### Example request — cross-account move

```json
{
  "name": "move_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "folder": "Notes",
    "account": "On My Mac"
  }
}
```

#### Limitations / notes

- **Same-account moves** preserve the original note ID and timestamps.
- **Cross-account moves** create a new note at the destination and delete the original. The note gets a **new ID**, **reset timestamps**, and **attachments may not transfer**.
- With `account` + `folder`, missing destination folders are auto-created.
- With `folder` only (no `account`), the folder must already exist — no auto-creation is performed.
- `title` in the response is best-effort and may be empty. Treat `id`, `account`, `path`, `folder`, and `modifiedAt` as authoritative.

---

## Folder Management

### `create_folder`

**Purpose:** Create a folder path with idempotent `mkdir -p` semantics.

#### Parameters

| Parameter | Type   | Required | Description                                    |
|-----------|--------|----------|------------------------------------------------|
| `folder`  | string | Yes      | Folder path (e.g. `"Projects/2025/Q1"`).       |
| `account` | string | No       | Account scope.                                 |

#### Example request — nested creation in a specific account

```json
{
  "name": "create_folder",
  "arguments": {
    "folder": "Projects/2025/Q1",
    "account": "iCloud"
  }
}
```

#### Example response

```json
{
  "account": "iCloud",
  "path": "Projects/2025/Q1",
  "name": "Q1",
  "parentPath": "Projects/2025",
  "depth": 2,
  "alreadyExisted": false
}
```

#### Example request — without account

```json
{
  "name": "create_folder",
  "arguments": {
    "folder": "Work/Reports"
  }
}
```

#### Limitations / notes

- Missing intermediate segments are created automatically.
- `alreadyExisted` is `true` only if **all** segments already existed.
- **Without `account`**, the first path segment must already exist in exactly one account. If it exists in multiple accounts, an ambiguity error is returned. If it exists in no account, an error asks you to provide `account`.
- There is no implicit default-account fallback for folder creation.
- Path matching is case-sensitive.

---

### `rename_folder`

**Purpose:** Rename a folder while preserving its parent location.

#### Parameters

| Parameter | Type   | Required | Description                                         |
|-----------|--------|----------|-----------------------------------------------------|
| `folder`  | string | Yes      | Current folder path (e.g. `"Work/OldName"`).        |
| `newName` | string | Yes      | New leaf name (must not contain `/`).                |
| `account` | string | No       | Account scope.                                      |

#### Example request

```json
{
  "name": "rename_folder",
  "arguments": {
    "folder": "Work/Drafts",
    "newName": "Archive",
    "account": "iCloud"
  }
}
```

#### Example response

```json
{
  "account": "iCloud",
  "oldPath": "Work/Drafts",
  "newPath": "Work/Archive",
  "name": "Archive",
  "parentPath": "Work",
  "depth": 1,
  "renamed": true
}
```

#### Limitations / notes

- System folders (`Notes`, `Recently Deleted`) cannot be renamed.
- `newName` **cannot contain `/`** — it is a leaf name, not a path.
- If `newName` equals the current leaf name, the operation is a no-op and returns `renamed: false`.
- Name conflicts with siblings in the same parent return a descriptive error.

---

### `move_folder`

**Purpose:** Move a folder (and its contents) into a destination parent folder. This is an orchestrated, non-atomic operation.

#### Parameters

| Parameter            | Type   | Required | Description                                                                                  |
|----------------------|--------|----------|----------------------------------------------------------------------------------------------|
| `folder`             | string | Yes      | Source folder path.                                                                          |
| `destinationFolder`  | string | Yes      | Destination **parent** path. The source folder name is appended automatically.               |
| `account`            | string | No       | Source account scope.                                                                        |
| `destinationAccount` | string | No       | Destination account scope. Defaults to source account.                                       |

#### Example request — same-account move

```json
{
  "name": "move_folder",
  "arguments": {
    "folder": "Work/Drafts",
    "destinationFolder": "Archive",
    "account": "iCloud"
  }
}
```

This moves `Work/Drafts` to `Archive/Drafts` in the iCloud account.

#### Example response

```json
{
  "sourceAccount": "iCloud",
  "sourcePath": "Work/Drafts",
  "destinationAccount": "iCloud",
  "destinationPath": "Archive/Drafts",
  "folder": "Drafts",
  "moved": true,
  "movedNoteCount": 3,
  "failedNoteMoves": [],
  "createdFolders": ["Archive/Drafts"],
  "sourceDeleted": true,
  "partial": false
}
```

#### Example request — cross-account move

```json
{
  "name": "move_folder",
  "arguments": {
    "folder": "Recipes",
    "destinationFolder": "Notes",
    "account": "On My Mac",
    "destinationAccount": "iCloud"
  }
}
```

#### Limitations / notes

- Use `"Notes"` as `destinationFolder` to move a folder to the top level of an account.
- **Non-iCloud accounts** typically only support top-level folders.
- The operation is **non-atomic** — it creates destination folders, moves notes one by one, then deletes the source. Partial failures are possible.
- The source folder is deleted **only if all note moves succeed**. If some fail, `sourceDeleted` is `false` and `partial` is `true`.
- `failedNoteMoves` contains details for each failed note: `{noteID, noteTitle, sourceFolder, destinationFolder, reason}`.
- Cycle protection prevents moving a folder into itself or its descendants (same-account only).
- No-op protection prevents moving a folder to its current parent in the same account.
- System folders (`Notes`, `Recently Deleted`) cannot be moved.

---

### `delete_folder`

**Purpose:** Delete a folder and all its contents (cascading delete).

#### Parameters

| Parameter              | Type    | Required | Description                                             |
|------------------------|---------|----------|---------------------------------------------------------|
| `folder`               | string  | Yes      | Folder path (e.g. `"Work/Drafts"`).                    |
| `confirmCascadeDelete` | boolean | Yes      | Must be literal boolean `true`.                         |
| `account`              | string  | No       | Account scope.                                          |

#### Example request

```json
{
  "name": "delete_folder",
  "arguments": {
    "folder": "Work/Drafts",
    "confirmCascadeDelete": true,
    "account": "iCloud"
  }
}
```

#### Example response

```json
{
  "account": "iCloud",
  "path": "Work/Drafts",
  "folder": "Drafts",
  "deleted": true
}
```

#### Limitations / notes

- `confirmCascadeDelete` must be **literal boolean `true`**. The string `"true"` is rejected. This is a deliberate safety gate.
- There is **no non-cascading mode**. All subfolders are deleted and all notes inside are moved to Recently Deleted.
- System folders (`Notes`, `Recently Deleted`) cannot be deleted.
- Notes moved to Recently Deleted are permanently removed by Notes.app after ~30 days.

---

## Common Workflows

### Search and read a specific note

1. Search for a note by title, narrowing by date:

```json
{
  "name": "list_notes",
  "arguments": {
    "searchText": "Sprint Retro",
    "searchIn": "title",
    "createdAfter": "2025-01-01",
    "createdBefore": "2025-01-31",
    "limit": 5
  }
}
```

2. Read the full note using the ID from the result:

```json
{
  "name": "get_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p200",
    "bodyFormat": "markdown"
  }
}
```

### Create a nested folder structure and add a note

1. Create the folder path:

```json
{
  "name": "create_folder",
  "arguments": {
    "folder": "Projects/2025/Q1",
    "account": "iCloud"
  }
}
```

2. Create a note in that folder:

```json
{
  "name": "create_note",
  "arguments": {
    "title": "Q1 Planning",
    "body": "## Goals\n\n- Launch v2\n- Reduce churn by 10%",
    "bodyFormat": "markdown",
    "account": "iCloud",
    "folder": "Projects/2025/Q1"
  }
}
```

### Move all notes from one folder to another

1. List all notes in the source folder:

```json
{
  "name": "list_notes",
  "arguments": {
    "account": "iCloud",
    "folder": "Work/Drafts",
    "limit": 0
  }
}
```

2. Move each note individually using the IDs from the result:

```json
{
  "name": "move_note",
  "arguments": {
    "id": "x-coredata://12345678-1234-1234-1234-123456789ABC/ICNote/p101",
    "folder": "Work/Archive",
    "account": "iCloud"
  }
}
```

Alternatively, use `move_folder` to move the entire folder (and its notes) at once:

```json
{
  "name": "move_folder",
  "arguments": {
    "folder": "Work/Drafts",
    "destinationFolder": "Work/Archive",
    "account": "iCloud"
  }
}
```

This moves `Work/Drafts` to `Work/Archive/Drafts` with all its notes.
