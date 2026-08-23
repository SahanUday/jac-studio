---
id: 2026-08-23-supplementary-plane-string-crashes-js-codegen
date: 2026-08-23
category: compiler-bug
severity: minor
status: open
phase: 1
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: "src/vs/base/common/strings.ts (containsRTL)"
upstream_issue: ""
tags: [translator, piece-tree, unicode, codegen]
---

## What we tried

Porting `containsRTL` (src/vs/base/common/strings.ts) as part of the piece-tree buffer's builder
support. Upstream's RTL-detection regex has a BMP character class plus four alternatives written
as UTF-16 surrogate pairs (e.g. `\uD802[\uDC00-\uDD1B]`) matching supplementary-plane RTL scripts.
Ported the BMP part directly (pure-ASCII escape text, mechanically pulled from the TS source) and
mechanically converted the four surrogate-pair alternatives into real Python/Jac codepoint-range
escapes (`\U00010800-\U0001091B`, etc., via the standard surrogate-decode formula) — the correct
translation, since Python `re` matches codepoints, not UTF-16 code units, and a literal
surrogate-pair transcription would silently never match any real string.

## What happened

Assigning a `str` global containing one of those `\U000XXXXX` escapes, then running `jac check`/
`jac test` on the file, crashes the compiler outright (not a diagnostic — a raw Python traceback):

```
UnicodeEncodeError: 'utf-8' codec can't encode character '\ud802' in position ...: surrogates not allowed
```

thrown from `jaclang/jac0core/codegen_ir.jac`'s `_w_str_entry`, reached via the ECMAScript codegen
pass (`esast_gen_pass.impl.jac`'s `exit_string`/`_str_literal`) while writing bytecode/output —
not from anything in the module being compiled. `jac check` alone (no `test`/`run`) on a minimal
repro (`glob X: str = "\U00010800";`, no test block) does NOT crash — the failure only surfaced
once a `test` block existed in the file, suggesting the crash path is specific to whichever
codegen stage runs for test execution (plausibly the client/JS-target compilation, since Jac
targets multiple placements and jac-studio's `jac.toml` doesn't obviously opt out of that pass).
The most likely mechanism: the codegen pass converts the supplementary-plane Python codepoint into
a UTF-16 surrogate pair (correct for JS string semantics) as an intermediate representation, then
a *different* step tries to UTF-8-encode that already-surrogate-split intermediate — UTF-8 cannot
represent a lone surrogate, by design (Python's own `str.encode('utf-8')` raises the identical
error), so this looks like an ordering/representation bug in the codegen pipeline rather than a
fundamentally unsupported feature.

**A second, sharper edge**: the crash reproduces identically for a `chr(0x10900)` *runtime* call
(not just a source-level literal), and — most surprising — for the escape sequence appearing only
as *prose inside a docstring* (`` `\ud802` `` written to describe the bug in a comment). Jac
decodes backslash-`u` escapes inside docstrings the same as any other string literal; writing the
literal escape text to document this very bug reproduces the crash recursively. Documenting it
required deliberately breaking the escape spelling (e.g. writing "U+D802" instead of the literal
sequence).

## Plan

Not filed upstream yet — the ordering-bug theory above is a guess from the traceback shape, not
confirmed by reading the codegen source; a jaseci maintainer would need to confirm whether this is
a real, fixable pipeline bug or a fundamental limitation of the current JS-target string encoding.
Worth a minimal repro (`glob X: str = "\U00010800"; test "t" { assert len(X) == 1; }`) if filed.

For this project: `contains_rtl` (`src/editor/core/strings.jac`) only ports the BMP part of
upstream's RTL-detection regex — the four supplementary-plane script ranges (Cypro-Minoan, Old
Uyghur, Kawi, Nag Mundari, and similar) are a documented, deliberate scope cut, not silently
dropped. This under-detects RTL for documents using those specific scripts; not a concern for
anything currently planned, but real functionality is missing and should be revisited once this
compiler bug is fixed rather than forgotten. General guidance for future translations: avoid
supplementary-plane (`\U000XXXXX`, code point ≥ U+10000) string literals anywhere in a `.jac` file
until this is resolved — including in comments/docstrings describing them, which need the escape
spelling deliberately broken up to avoid re-triggering the same crash while documenting it.
