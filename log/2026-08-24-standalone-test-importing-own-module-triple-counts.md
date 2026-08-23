---
id: 2026-08-24-standalone-test-importing-own-module-triple-counts
date: 2026-08-24
category: compiler-bug
severity: minor
status: workaround
phase: 1
subsystem: tooling
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-test, test-discovery, tooling, phase-1]
---

Found while investigating whether `src/editor/*`'s colocated `<mod>.test.jac` annex files could be
moved into a `tests/` subdirectory (mirroring `service-registry-spike/tests/`) without regressions.
Confirmed against `jac guide jac-testing` and `jac guide reference/testing`, not just empirical
trial -- neither guide documents this.

**What was found**: a standalone test file (not a `.test.jac` annex) that both (a) lives in a
`tests/` subdirectory and (b) `import from`s the module it's testing -- required, since a
standalone file doesn't get the annex's implicit no-import scope access -- gets triple-counted
under this project's actual real-world `jac test` invocation (bare `jac test`, no args, which
honors `jac.toml`'s `[test] directory = "src"` and walks the whole tree recursively).

Minimal repro: moved `src/editor/core/char_code.test.jac` (3 tests, no imports, relying on annex
scope) to `src/editor/core/tests/char_code_tests.jac`, added
`import from src.editor.core.char_code { TAB, LINE_FEED, CARRIAGE_RETURN }` (required -- without
it, `NameError: name 'TAB' is not defined`). Ran `jac test -v` from the repo root:

```
PASSED   constants match upstream numeric values  [.../src/editor/core/char_code.jac]
PASSED   constants match ord() of their real characters  [.../src/editor/core/char_code.jac]
PASSED   constants are distinct  [.../src/editor/core/char_code.jac]
PASSED   constants match upstream numeric values  [.../src/editor/core/tests/char_code_tests.jac]
PASSED   constants match ord() of their real characters  [.../src/editor/core/tests/char_code_tests.jac]
PASSED   constants are distinct  [.../src/editor/core/tests/char_code_tests.jac]
PASSED   constants match upstream numeric values  [.../src/editor/core/tests/char_code_tests.jac]
PASSED   constants match ord() of their real characters  [.../src/editor/core/tests/char_code_tests.jac]
PASSED   constants are distinct  [.../src/editor/core/tests/char_code_tests.jac]
```

Nine passes reported for three real `test` blocks: two full occurrences correctly attributed to
the actual file (`tests/char_code_tests.jac`, itself double-run), plus a third occurrence
misattributed to `char_code.jac` -- the plain module file, verified to contain zero `test` blocks
(`grep -c '^test ' char_code.jac` -> `0`). Total suite count moved from a real baseline to
`+6` inflated passes for this one file alone. Isolated to the combination of both conditions:
a colocated annex re-tested with the same content (no move, no import) shows no duplication, and a
standalone file that does NOT import its subject module doesn't hit this path either (it just fails
with `NameError` instead, per the annex-scope requirement).

**Why this matters**: it's not just a display glitch -- misattributing a passing test to the wrong
source file would silently corrupt any tooling built on `jac test`'s per-file output (coverage-by-
file, "which module owns this failure" triage), and duplicate execution is a real risk for any test
with side effects (persisted graph writes, counters), not just pure `assert`s like this repro.
It directly blocks the `src/editor/*` colocated-annex layout from ever being reorganized into a
separate `tests/` tree the way `service-registry-spike/` uses, since the annex-to-standalone
conversion this would require is exactly what triggers it.

**Plan**: workaround is simply not doing the conversion -- keep `src/editor/*`'s `<mod>.test.jac`
annex layout as-is; it doesn't hit this path at all. Not escalating to jaseci yet since it's narrow
(only matters if someone actually wants standalone test files that both live in a subdirectory and
import their own subject module) and jac-studio has no current need to do that. Revisit if a future
phase's test organization genuinely needs the standalone-in-subdirectory shape -- at that point this
would need a real upstream report with the minimal repro above, since app-level workarounds (e.g.
avoiding the self-import somehow) aren't really available: the import is required by the language
for a standalone file to see the module's symbols at all.
