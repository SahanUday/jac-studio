---
id: 2026-08-31-useeffect-explicit-none-return-crashes-as-non-function-destroy
date: 2026-08-31
category: compiler-bug
severity: minor
status: resolved
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, react, useEffect, none, output-panel]
---

## What happened

Building Phase 4's Output panel, `src/workbench/output/output.jac`'s `useEffect` polls a channel
on an interval only while its panel tab is the active one, written the natural Python-flavored way:

```jac
useEffect(lambda {
    if not active {
        return None;
    }
    refresh();
    interval_id = setInterval(lambda { refresh(); }, 2000);
    return lambda { clearInterval(interval_id); };
}, [active, selected_channel]);
```

`jac check`/`jac test` both passed. Live in a real browser (`jac browse` against
`jac run --serve --dev`), the moment this effect re-ran with `active` toggling (opening the panel
for the first time), React crashed the whole app through its error boundary:

```
TypeError: destroy is not a function
    at safelyCallDestroy (.../chunk-NI3L4CFM.js:16796:13)
    at commitHookEffectListUnmount (.../chunk-NI3L4CFM.js:16923:19)
```

## Root cause

`return None;` lowers verbatim to `return null;` in the compiled JS (confirmed by reading
`compiled/src/workbench/output/output.js` directly). That is not a jac2js bug -- it is a correct,
literal translation of what the source says. The actual mismatch is with React's own contract:
`useEffect`'s callback may return either a cleanup **function** or nothing at all (a bare
`return;`/falling off the end, i.e. JS `undefined`) -- an explicit `return null;` is neither, and
React 18 treats "returned something, but it isn't a function" as an error, not as "no cleanup."
Python-flavored jac code reflexively reaches for `return None;` to mean "return nothing," which is
correct everywhere else in this project but not inside a `useEffect` callback specifically.

## Fix (shipped)

Return an actual no-op cleanup function on every path instead of `None` on the early-exit one:

```jac
useEffect(lambda {
    if not active {
        return lambda {};
    }
    refresh();
    interval_id = setInterval(lambda { refresh(); }, 2000);
    return lambda { clearInterval(interval_id); };
}, [active, selected_channel]);
```

Confirmed fixed live: the same open-panel interaction no longer throws, and the interval starts/
clears correctly across `active` toggling.

## Plan

`resolved`, not `workaround-found` -- this is the correct, permanent pattern (always return a real
cleanup function, or a bare `return;` with no value, from a conditional `useEffect` body), not a
stopgap around a Jac defect; every other `useEffect` already in this project (`terminal.jac`'s
`ResizeObserver`, `workbench.jac`'s keydown listener) happens to return unconditionally so none of
them had hit this. Worth adding to `jac-language`'s gotcha list verbatim next time that skill is
touched: **a conditional early-return inside a `useEffect` callback must return a cleanup function
(or nothing) on every branch -- `return None;` on one branch and a real cleanup lambda on another is
a live-only crash, invisible to `jac check`/`jac test`.**
