<INSTRUCTIONS>
## Coding style
- Use 2 spaces for indentation in new or modified code.
- Prefer clarity over brevity. Use concise names, but avoid cryptic abbreviations.

## Documentation
- Any code modification should trigger an update to documentation where applicable.
- Document behavior, inputs/outputs, and non-obvious decisions.
- Skip documentation for trivial or self-evident code.

## Apple Notes Design Gotchas

### Body HTML contains the title
Apple Notes stores the visible title as the first heading element in body HTML.
When creating notes via AppleScript, only set `body` — never set `name` in
the creation properties, or the title appears twice. After creation, `name`
can be set separately if metadata sync is needed (as `create_note` does with
`{name:"", body:bodyValue}` followed by `set name of n to titleValue`).

### Cross-account move is create + delete
Apple Notes does not support direct cross-account moves. The code detects
whether the note belongs to the destination account; if not, it creates a
new note at the destination using `{body:originalBody}` (without `name`) and
deletes the original. Consequences: the note gets a new ID, timestamps reset,
and attachments may not transfer.

### Cross-account folder auto-creation
In scoped (account-provided) cross-account moves, missing destination folders
are auto-created segment by segment. Unscoped (folder-only) moves require
the folder to already exist and will error with `folderNotFound` if missing.
</INSTRUCTIONS>
