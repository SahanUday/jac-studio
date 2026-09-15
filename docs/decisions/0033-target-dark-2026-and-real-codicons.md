# 0033 — Target "Dark 2026"/"Light 2026" and the real `@vscode/codicons`

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Derive the palette from VS Code's *actual* current defaults, "Dark 2026"/"Light 2026", and ship
the real `@vscode/codicons` font rather than a Codicons-alike. `@hugeicons` removed.

## Why

**CORRECTION** to 0032, found by checking the live `microsoft/vscode` source instead of assuming:
`ThemeSettingDefaults.COLOR_THEME_DARK`/`_LIGHT` in `workbenchThemeService.ts` resolve to
`'Dark 2026'`/`'Light 2026'`. The two are materially different, not a palette tweak — the 2026
default drops the classic bright-blue status bar entirely (`statusBar.background: #191A1B`; blue
`#3994BC` now only marks a debugging session), uses a muted teal-blue accent `#297AA0` instead of
`#007acc`, and uses translucent overlays (`list.hoverBackground: #FFFFFF14`) for hover/selection.

## Consequences

Chrome colors are hand-edited exact values per `jac retheme`'s documented one-off escape hatch
(`--baseColor zinc --theme sky --radius small` as the closest preset scaffold) — its OKLCH inputs
are presets only. A future session restoring "VS Code blue" would be reverting to a palette
upstream no longer ships. `jac install --shadcn <name>` silently reintroduces `@hugeicons` into
every newly generated primitive; check each new one.
