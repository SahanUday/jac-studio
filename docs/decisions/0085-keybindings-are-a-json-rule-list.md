# 0085 — Keybindings are a `keybindings.json` rule list over the built-in defaults

- **Date**: 2026-10-07
- **Status**: accepted

## Decision

User keybindings are `keybindings.json` in the user data dir ([0082](0082-user-level-state-lives-in-json-files.md)),
in VS Code's format: a list of `{key, command, when}` rules. A `command` starting with `-` removes
that command's default binding for `key`; later rules win. `list_commands` merges the file over each
command's built-in bindings on every call and tags each binding `default` or `user`.

- **Chords are canonical strings**: modifiers in `ctrl`, `shift`, `alt` order then one key
  (`ctrl+shift+p`). `chord_from_event` builds them for both the global key handler and the shortcut
  recorder, so what you record is exactly what later matches; the server normalises hand-edited
  keys to the same form. Key *sequences* (`ctrl+k ctrl+s`) are rejected, not silently ignored.
- **The Keyboard Shortcuts tab** lists every command with key, when-clause and source, searches by
  title, id or key, and records a new chord (Enter accepts, Escape cancels). Another command already
  on that chord is flagged, not blocked, as in VS Code.
- **Bad input never breaks startup**: malformed rules and unparseable files are skipped.
- **Only commands in `BUILTIN_COMMANDS` are returned.** A node for a removed command stays in the
  graph but is hidden, and `register_command` writes only when a value changed, because concurrent
  callers each rewriting unchanged nodes raised `WriteConflict`.

## Why

Replaces the graph `KeybindingOverrides` node, which had no UI and the persistence problems
[0084](0084-settings-are-json-files-with-a-schema.md) already moved settings off. The VS Code rule
format makes user files portable in both directions and gives "remove a default" a clean spelling.

## Consequences

- Editor shortcuts that Monaco binds itself (Undo, Find, Format, ...) are not in the table and are
  not rebindable; the menu shows them as static hints.
- Some browser shortcuts (Ctrl+W, Ctrl+T, Ctrl+N) cannot be captured.
- The old graph overrides are not migrated: nothing could set them, so none exist in practice.
