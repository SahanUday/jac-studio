# 0082 — User-level state lives in JSON files under the user data dir

- **Date**: 2026-10-07
- **Status**: accepted

## Decision

State that belongs to the person, not to a workspace or a jac `root`, is stored as plain JSON under
`$JAC_STUDIO_CONFIG_DIR`, else `$XDG_CONFIG_HOME/jac-studio`, else `~/.config/jac-studio`
(`src/workbench/user_data/user_data.jac`): per OS user, like VS Code's own user data.

| File | Holds | Since |
|---|---|---|
| `workbench-state.json` | recent workspaces, the show-welcome-on-startup preference | this ADR |
| `settings.json` | user settings (replaces the graph `Settings` node) | next: settings editor |

Writes go through a temp file and rename; a missing or corrupt file reads as defaults.

## Why

The graph store has had repeated persistence bugs (stuck flags, lost edges, duplicate nodes: see
`known-limitations.md`), and recents must survive them. Settings as a hand-editable `settings.json`
is also VS Code's model, which the settings editor needs for its "Open settings.json" and
user/workspace layering.

## Consequences

- Two jac users on one OS account share recents and settings. Accepted: jac-studio is local and
  single-user, as the terminal gate already assumes.
- The existing graph settings migrate once when `settings.json` lands.
- Workspace and session state stay on the graph for now.
