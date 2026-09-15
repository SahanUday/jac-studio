# 0057 — Multi-file edit review v1 is a per-file diff preview, not a checkpoint timeline

- **Date**: 2026-09-03
- **Status**: accepted

## Decision

Show a real Monaco diff inside each `Edit`/`Write` approval card, computed in the launcher before
the tool call runs (`_diff_preview_for_tool_call`: on-disk content as `original_text`, the tool's
own apply semantics for `modified_text`). Upstream's `chatEditing/` checkpoint/timeline machinery
(20 files) stays out of scope.

## Why

A per-file before/after preview closes the actual risk — an agent silently overwriting a file the
user did not expect — without the rollback machinery. Both tool input shapes were confirmed live,
not assumed (`Write`: `file_path`/`content`; `Edit`: `file_path`/`old_string`/`new_string`/
`replace_all`). A possible `MultiEdit` tool was probed for, the probe timed out inconclusively, so
it is deliberately left unspecialized rather than guessed at.

## Consequences

Built on 0056's interception point; `ai_tool_diff_preview.jac` reuses `scm_diff_editor.jac`'s
synthetic-model-URI pattern but keys by `tool_use_id`, not file path, since multiple concurrent
requests can target the same file. Renders unified (`renderSideBySide: False`) because the card
lives in a narrow sidebar.
