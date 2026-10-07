# 0083 — The title bar gets a VS Code-style menu bar

- **Date**: 2026-10-07
- **Status**: accepted

## Decision

`src/workbench/menu_bar/` adds File, Edit, Selection, View, Go, Run, Terminal and Help menus to the
title bar, on shadcn's Radix `Menubar` (installed with `jac install --shadcn menubar`, icons swapped
to codicons). This reverses the "no menu bar" half of [0040](0040-activity-bar-is-a-hand-built-switcher.md).

- **A menu item is a command id.** Menu, palette and keybinding all dispatch through
  `workbench.jac`'s `handle_command`; Monaco actions (Undo, Find, Format, Go to Line, ...) are
  registered as commands too and run on the active editor by `run_editor_command`.
- **Only working items are listed.** Items needing a folder or an editor are disabled, not hidden.
  Cut/Copy/Paste are left out: browsers block script-driven paste, and a menu item that only works
  sometimes is worse than none.
- **The theme class is mirrored onto `<body>`** (`main.jac`), because Radix portals mount there,
  outside the themed root div ([0068](0068-paint-theme-colors-at-the-root-div.md)
  anticipated this gap).

## Why

0040 left the menu bar out because "the browser owns window chrome", but a menu bar is not window
chrome: it is the discoverable index of commands, and the goal is VS Code's interface. The browser
tab supplies the window controls; it never supplied menus.

## Consequences

- No Alt-key mnemonics, no submenus (Open Recent is one dialog), no overflow "..." menu on narrow
  widths: the Command Center pill shrinks first.
- Palette gains the Edit/Selection/Go commands, searchable by title.
