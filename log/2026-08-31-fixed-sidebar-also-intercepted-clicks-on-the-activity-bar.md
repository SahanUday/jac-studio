---
id: 2026-08-31-fixed-sidebar-also-intercepted-clicks-on-the-activity-bar
date: 2026-08-31
category: ergonomics
severity: major
status: resolved
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [shadcn, sidebar, z-index, position-fixed, click-through, activity-bar, search]
---

## What happened

Running PR #49's own test plan for real (`jac run --serve --dev` + `jac browse`, real mouse-
coordinate clicks rather than accessibility-tree refs), the Search tab in `activity_bar.jac` was
not clickable at its real on-screen position:

```
jac browse click @e14
✖ Error: browser error: @e14 not actionable: point (24,102) is covered by div
```

`elementFromPoint` at that exact coordinate resolved to a file-tree `treeitem`, not the activity
bar's own tab button. Checking the pre-existing Explorer tab (unrelated to this PR, already shipped
in Phase 3) at *its* real coordinates found the identical symptom -- this was never introduced by
Search, just never caught before because nothing had tried a real mouse click at those exact
coordinates until this verification pass.

## Root cause

The same one already logged in `2026-08-31-fixed-sidebar-overlaps-and-intercepts-clicks-on-bottom-panel`:
`components/ui/sidebar.jac`'s vendored desktop wrapper (`jac install --shadcn sidebar`-generated)
is `position: fixed; inset-y-0; z-index: 10; width: (--sidebar-width)`, spanning the *entire*
viewport height at the left edge regardless of what else occupies that horizontal column elsewhere
in the page. That entry only fixed the *bottom panel* instance of this overlap; the activity bar
sits in the identical 0-48px horizontal column, just higher up the page (`y: 30-126` vs. the
panel's `y: ~480+`), with no z-index of its own to contest the fixed sidebar's `z-index: 10`. Two
separate instances of the same underlying cause, not a new root cause.

## Fix (shipped)

Same fix as the bottom panel, applied to `activity_bar.jac`'s own root element this time:
`position: relative; zIndex: 20`. Confirmed live: `elementFromPoint` at both the Explorer and
Search tab's real coordinates now resolves to the tab button (or a child inside it) rather than
the file-tree layer beneath, and a real ref-based `jac browse click` succeeds without the
`not actionable` error.

## Plan

`resolved`, not a new open question -- this is the exact same fix pattern as the already-logged
bottom-panel entry, just a second call site. Worth treating as a signal rather than closing the
book on this class of bug: **any hand-built chrome element sharing the sidebar's own 0-48px (or
0-`--sidebar-width`) horizontal column should be checked for the same overlap** the next time one
is added or touched -- the title bar and status bar's own leftmost regions haven't been explicitly
re-verified against this specific coordinate range yet, and neither has been the notification
bell's Sheet trigger (flagged as unverified in the bottom-panel entry's own Plan section). A single
shared fix at a higher level (e.g. the flex row wrapping the activity bar in `workbench.jac`, or a
project-wide z-index scale) would close this class of bug for good instead of patching it piece by
piece as each new element happens to get verified against real mouse coordinates.
