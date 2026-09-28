---
id: 2026-09-28-client-test-directory-discovery-breaks-cross-file-binding
date: 2026-09-28
category: compiler-bug
severity: major
status: upstream-tracked
phase: 8
subsystem: tooling
jac_version: "0.37.23 (also reproduced on jaseci main @061c73f8b68db44b843ab4c164933db110c78d38)"
related_vscode_ref: ""
upstream_issue: "jaseci-labs/jac#9606"
tags: [jac-test, client-placement, jac2js, test-runner]
---

Bumping jac-studio's pinned `jac` from `0.37.3` to `0.37.23` (tracking `main` more closely --
`0.37.3` was ~300 commits behind) regressed `jac test src` from `503 passed` to `503 passed, 1
error`. The one failure: `src/editor/client/breadcrumb_symbols.jac` (a client-pinned, zero-import,
pure-function module) fails to compile its test bundle with `Client codegen emitted the builtin
'len' unlowered` -- but `jac test src/editor/client/breadcrumb_symbols.jac` alone passes cleanly on
both `0.37.3` and `0.37.23`.

Minimal external repro (isolated outside jac-studio entirely, see the upstream issue for full
files/jac.toml): two files, `a.jac` (pinned `client`, defines `check_len` calling `len()`) and
`b.jac` (default placement, unrelated `add`), each with one `.test.jac`. `jac test .` from that
directory fails `a`'s test with `ReferenceError: check_len is not defined` inside the generated
`harness.mjs` -- a different symptom than jac-studio's `len unlowered`, but gated by the exact same
three conditions, so very likely the same root defect surfacing differently depending on what a
previously-processed file's harness left behind:

1. Directory-based test discovery (`jac test .` / `jac test <dir>`) -- explicit file args
   (`jac test a.jac b.jac`) always pass.
2. A second `.test.jac` present in that directory (any placement) -- with only `a.test.jac` present,
   `jac test .` passes.
3. The failing module carries `client` placement -- remove the `[placement.pins]` entry and both
   tests pass under directory discovery too.

Ruled out: worker concurrency. `-j 0` and `-j 1` fail identically to the default job count, so this
isn't a race over a shared temp dir between parallel workers -- it's deterministic, not
intermittent.

**Plan**: Filed upstream ([jaseci-labs/jac#9606](https://github.com/jaseci-labs/jac/issues/9606))
with the full repro. No workaround applied in jac-studio -- `jac test src` runs the whole
directory in CI and will show this one failure honestly until upstream fixes it, rather than
skipping/xfail-ing the test to paper over a real compiler defect. Revisit once the issue is
triaged; re-run `jac test src` after any jac bump to confirm it's cleared.
