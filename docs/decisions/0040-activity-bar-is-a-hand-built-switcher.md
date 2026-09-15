# 0040 — The activity bar is a hand-built view switcher, not the `Sidebar` primitive

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Build `src/workbench/activity_bar/activity_bar.jac` (and `title_bar/title_bar.jac`) by hand.
`VIEWS` is a plain module-level list; the switching mechanism (`active_view_id` owned by
`workbench.jac`, one `onSelectView` callback) is built end to end even though only Explorer
exists so far.

## Why

A correction to 0005's mapping table, which had folded "activity bar" into the same row as
`Sidebar` — wrong, because `Sidebar` is a container, not a view *switcher*. Found by a live-source
check against `microsoft/vscode` (`gh api`): `workbench/browser/parts/*` — holding `activitybar`,
`titlebar`, `auxiliarybar` and `notifications` — had never been triaged at all, the triage doc
having scoped itself to the two `contrib` trees.

## Consequences

Later views (Search, SCM, Outline, Debug) are a one-entry-plus-one-branch addition, which held in
practice. The title bar ships with no window controls and no menu bar (a web app, not a native
host). Building it also forced `command_palette.jac`'s private `open` state up into
`workbench.jac` so the keyboard shortcut and the Command Center pill dispatch through one path.
