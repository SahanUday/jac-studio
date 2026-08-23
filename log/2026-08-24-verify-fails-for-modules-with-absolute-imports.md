---
id: 2026-08-24-verify-fails-for-modules-with-absolute-imports
date: 2026-08-24
category: translator-blocker
severity: minor
status: workaround
phase: 1
subsystem: translator
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [translator, verify, imports, phase-1]
---

Found while restructuring `src/editor/*` into Jac's declaration/implementation idiom (a pure
structural refactor, unrelated to this bug -- confirmed below by reproducing against the
completely unmodified original files before any restructuring was applied).

**What was found**: `translator/main.jac -- verify --id <id>` runs `jac test <jac_path>` as a
subprocess from inside `translator/`. For any module using an absolute `src.editor...`-rooted
import (e.g. `piece_tree_base.jac`'s `import from src.editor.core.char_code {...}`), that
subprocess fails with `ModuleNotFoundError: No module named 'src.editor'` and `verify` marks the
module `blocked` -- even though the module is completely correct and its tests pass fine. Absolute
imports rooted at `src` resolve against the repo root, but `verify`'s subprocess runs with
`translator/` as its working directory, which has no `src/` of its own.

Confirmed via two checks:
1. Reproduced identically against the pristine, unmodified `piece_tree_base.jac` and
   `piece_tree_text_buffer.jac` (git-stashed my restructuring changes first) -- same
   `ModuleNotFoundError`, same failure, nothing to do with today's refactor.
2. `interval_tree.jac` (no imports at all -- fully self-contained) verifies fine
   (`'interval-tree' verified and marked landed`), confirming the failure is specifically tied to
   absolute cross-file imports, not a general regression in the tool.

Every module that imports across the `model/`/`core/` package boundary this way is affected:
at minimum `piece-tree-base` and `piece-tree-text-buffer` (both confirmed); `piece-tree-text-
buffer-builder` and `text-model-search` likely share the same shape but weren't individually
re-checked. `jac check <path>` and `jac test <path>` run directly (not through `verify`) work
correctly for all of these regardless -- this is purely a `verify` subprocess-invocation gap, not
a real problem with the ported code.

**Impact**: a `blocked` status written by a failed `verify` run is a false signal for these
modules -- they are landed and working, `verify` just can't currently confirm it. A `git checkout
-- translator/manifest.toml` after any failed `verify` attempt on one of these modules is required
to avoid committing the spurious status flip (this happened twice while investigating this very
bug, each time reverted before committing).

**Plan**: workaround is simply not trusting `verify`'s `blocked` verdict for modules with absolute
`src.editor...` imports -- confirm with `jac check`/`jac test` run directly against the file
instead, and manually keep `manifest.toml`'s `status` at its correct value. Not fixing the
subprocess cwd/import-root handling in `translator/main.jac` itself right now -- out of scope for
the restructuring work that surfaced this, and the workaround is cheap. Worth fixing before the
translator is used heavily again in a later phase (its whole value proposition depends on `verify`
being trustworthy); the fix is likely either invoking the subprocess from the repo root instead of
`translator/`, or passing an explicit import-root flag to `jac test`.
