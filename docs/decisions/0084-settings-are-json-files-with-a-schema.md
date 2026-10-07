# 0084 — Settings are `settings.json` files, validated against one schema

- **Date**: 2026-10-07
- **Status**: accepted

## Decision

Settings live in two plain JSON files, merged over the schema defaults (workspace over user over
default), as in VS Code:

| Scope | File |
|---|---|
| User | `settings.json` in the user data dir ([0082](0082-user-level-state-lives-in-json-files.md)) |
| Workspace | `<workspace>/.jac-studio/settings.json` |

- **One schema** (`settings_schema.jac`) defines every key's type, default, range, options, category
  and description. The service validates writes against it; the Settings editor renders from it over
  RPC, so a setting exists in exactly one place.
- **Bad input never breaks startup.** A hand-edited value that is unknown or fails validation is
  skipped and the default used; a non-object or unparseable file reads as empty.
- **`workbench.startupEditor` replaces the Welcome tab's own preference** (0082's
  `showWelcomeOnStartup`), so there is one place to turn it off.
- **The old graph `Settings` node is read once** to migrate known values into the user file, then
  emptied so they can't resurrect if the file is deleted. No node is created on a fresh install.
- Consumers: Monaco options (font, tab size, wrap, line numbers, minimap, whitespace) are applied
  live to every editor; `editor.formatOnSave`; the terminal font size; the colour theme.

## Why

Supersedes the settings half of [0028](0028-persist-state-by-graph-reachability.md). The graph store
had no editable form, no scope layering, and the persistence bugs in `known-limitations.md`; a
settings editor with "Open settings.json" needs real files. One schema avoids the key list drifting
between the validator, the editor and the docs.

## Consequences

- An external edit to the **user** `settings.json` (outside the workspace watcher) applies on reload
  or on the next change in the app; saving it in an editor tab applies at once.
- Only settings that something reads are in the schema. Adding one is a schema entry plus its
  consumer.
- `editor.tabSize` yields to indentation detected from the file, as in VS Code.
