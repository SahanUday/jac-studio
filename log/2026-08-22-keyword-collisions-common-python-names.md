---
id: 2026-08-22-keyword-collisions-common-python-names
date: 2026-08-22
category: ergonomics
severity: minor
status: resolved
phase: 0
subsystem: tooling
jac_version: "0.36.1 (jac dev build)"
related_vscode_ref: ""
upstream_issue: ""
tags: [keywords, python-interop, argparse, translator]
---

Building the translator's CLI (`translator/main.jac`, wrapping Python's `argparse` and `re`) hit
three separate Jac-keyword collisions with extremely common Python API vocabulary, all within
about 150 lines of ordinary Python-interop code:

- `re.match(...)` — `match` is reserved (Jac's structural pattern matching), so calling it as a
  plain attribute/method on the `re` module needs escaping: `` re.`match(...) ``.
- `argparse.ArgumentParser.add_argument(..., default=...)` — `default` is reserved, needs
  `` `default=... `` at every call site (five occurrences in this one file).
- `sys.exit(...)` — see the companion entry (`2026-08-22-entry-exit-keyword-doc-mismatch.md`);
  `exit` needed the same escaping as an attribute access.

Each individually is documented (`jac-core-cheatsheet.md`'s "Reserved keywords cannot be used as
variable or parameter names" section, plus the backtick-escape mechanism), and none were hard to
fix once diagnosed — `jac check`'s error messages named the exact keyword and the exact escape
syntax needed every time. But the *pattern* is worth naming: `match`, `default`, `type`, `exit`,
`entry` are all common parameter/method names across the Python standard library and popular
packages (`argparse`, `re`, `sys`, and surely others not hit yet), so any Jac code wrapping
existing Python APIs via interop should expect to hit several of these per file, not as rare
edge cases.

**Impact on jac-studio**: minor, ongoing tax rather than a blocker — expect this same category of
friction throughout Phase 0+ wherever Python interop wraps a stdlib or PyPI API with common
parameter names. Not worth a design change; worth knowing to expect at code-review time.

**Workaround**: backtick-escape (`` `default ``, `` `match ``, `` `exit ``) at every call site
that needs one; `jac check`'s diagnostics identify these precisely, so this is mechanical, not
exploratory. `status: resolved` since all instances were fixed and the tool now compiles/runs
clean — logged as a pattern to expect, not an open problem.
