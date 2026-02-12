# InkNotes MCP: Turning Apple Notes into an Agent-Ready Knowledge Layer

I built this project to solve a personal problem and to understand MCP deeply by building a production-quality server end to end.

I have more than 250 notes in Apple Notes across multiple accounts. Finding what I need manually is slow, context switching is expensive, and most note-taking workflows are optimized for humans browsing, not for agents reasoning over content.

This article is the high-level story behind the release: why I built it, what gaps I found in existing options, what technical choices mattered, and what this MCP can do in practice.

## 1) Why I Built This

Two motivations drove the project:

- Practical: I wanted faster retrieval and manipulation of my own notes without manually digging through folders.
- Technical: I wanted to learn how MCP servers actually work in real-world conditions, not just in toy examples.

Apple Notes was the right domain because it combines structured data (accounts/folders/metadata), unstructured content (rich note bodies), and platform-specific constraints (AppleScript + macOS automation permissions).

## 2) What Existed, What Was Missing

There are existing Apple Notes MCP implementations and scripts. They were useful references, but they typically missed one or more of the following:

- comprehensive tool coverage for real workflows
- deterministic error handling and validation
- test depth and maintainability
- robust handling of Apple Notes edge cases and account/folder semantics

I wanted a version that could be trusted in daily use and extended safely over time.

## 3) What This MCP Actually Does

The server runs as a stdio JSON-RPC MCP process and exposes 14 tools across discovery, retrieval, writing, movement, and deletion.

Highlights:

- Account and folder discovery (`list_accounts`, `list_folders`)
- Note retrieval (`list_notes`, `get_note`, `batch_get_notes`)
- Note creation and updates (`create_note`, `update_note`)
- Note and folder movement (`move_note`, `move_folder`)
- Single and batch deletion (`delete_note`, `batch_delete_notes`, `delete_folder`)
- Folder lifecycle management (`create_folder`, `rename_folder`)

`list_notes` now supports date-range filtering with inclusive boundaries:

- `createdAfter`, `createdBefore`
- `modifiedAfter`, `modifiedBefore`

The server also supports body formatting modes (`plain`, `markdown`, `html`) and works across all accounts visible in Apple Notes, including iCloud, On My Mac, and Google-backed accounts.

## 4) Design Principles

The implementation follows a few explicit principles:

- Deterministic behavior over implicit magic.
- Strict input validation with clear error surfaces.
- Reusable orchestration of tools over duplicated brittle logic.
- Concurrency safety with Swift 6 + strict checking.
- Main-actor isolation for AppleScript execution.

For operations with higher failure risk, the server uses structured partial-success models rather than pretending everything is all-or-nothing.

## 5) Tooling Overview

The toolset is intentionally grouped by capability:

- Discovery: account and folder topology.
- Read: metadata-first listing plus full note fetches.
- Write: create/update with format-aware body handling.
- Move: note-level and folder-level movement semantics.
- Delete: single and batch deletion with explicit safety behavior.
- Folder management: create, rename, and scoped operations.

This structure keeps the MCP intuitive for users while keeping implementation units testable and composable.

## 6) Real Workflows (From Examples)

Representative workflows from examples include:

- Find notes created in a date range that mention a topic.
- Fetch a small set of candidate notes with body content for deeper analysis.
- Move notes and folders across account/folder scopes.
- Perform batch retrieval or deletion with explicit reporting of missing/failed items.

These workflows map to practical tasks, not just demo calls.

## 7) Hard Problems and Constraints

A few constraints shaped the architecture:

- AppleScript object references can behave unexpectedly across mutations.
- Automation/TCC permission behavior depends on the actual host process launching the MCP.
- Apple Notes body HTML is a specialized dialect; formatting and conversion require explicit handling.
- Some folder operations are safer as orchestrated workflows than monolithic scripts.

The implementation choices prioritize correctness and debuggability under those constraints.

## 8) Quality and Reliability

This release emphasizes engineering quality, not only feature count:

- Unit and integration test coverage across tool behavior and edge cases.
- Clear validation contracts for each tool.
- Structured error mapping for actionable failure messages.
- Safety gates for destructive actions.
- Consistent serialization contracts for MCP clients.

At the current state, the project has 302 passing tests across 24 suites.

## 9) What I Learned Building an MCP

The biggest lesson is that building an MCP is not primarily about wiring JSON-RPC handlers. The real work is in domain semantics:

- deciding what contracts tools should expose
- handling partial failure and retries
- mapping platform quirks into stable abstractions
- preserving correctness as capabilities grow

That is where a prototype becomes an actual product.

---

This is the high-level version. The next pass can expand each section with concrete call traces, design tradeoffs, and implementation details.
