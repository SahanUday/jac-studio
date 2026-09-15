---
name: jac-studio-testing
description: This skill should be used when writing, extending, reviewing, or restructuring any test in jac-studio — before adding a .test.jac file, when a bug fix needs a regression test, when deciding whether a change needs a new test at all, and when reporting test results in a PR. Covers the project's test policy, where tests must live, and which claims a passing `jac test` does NOT support.
---

# Test policy

## Before writing anything

1. **Read the existing tests first.** Tests live in a `<mod>.test.jac` annex beside the module, so
   coverage is deterministic to find — check there before assuming none exists.
2. **A bug fix extends an existing test.** Add a case to the existing table if there is one; a new
   `test` block only when the bug is a genuinely distinct path worth naming.
3. **A new test file is for a genuinely uncovered path** — justify it in the PR. This governs churn
   in already-covered code. It is **not** a brake on the untested surface: all workbench UI,
   `monaco_editor.jac`, most editor providers and all of `components/ui/` have no tests at all, and
   new coverage there is wanted, not merely tolerated.
4. **Table-driven over one-test-per-input.** A list of input/expected tuples iterated in one `test`
   block, not twenty near-identical blocks. For a large mechanical table, generate the cases from
   the source data with a script rather than hand-transcribing.
5. **Reuse fixtures and match the sibling setup** in neighbouring test files. `testing-workspace/`
   (repo root, gitignored) is the standing realistic fixture — use it instead of inventing a
   throwaway `/tmp` project.
6. **Prove it in-process where an in-process test can prove it** — no subprocess, server or
   cluster test just for realism. See the two exceptions below, which are not optional.
7. **Report pass counts before and after.** A fix PR normally keeps the same count; justify an
   increase. A *drop* is a transcription bug in your own change, not a regression to accept —
   find it.

## Mechanics that are not negotiable

- **`<mod>.test.jac`, colocated.** Never move a test annex to tidy a directory: `jac test
  <mod>.jac` auto-discovery and the translator's `verify` both require it there.
- **Never name a file `test_*.jac`** (collides with Python discovery). Standalone tests are
  `<name>_tests.jac`.
- **An annex never imports the module it tests.** It already sees those declarations, and
  importing anyway breaks unrelated `jac run` calls in the same project.
- **Run `jac test` or `jac test src`, never `jac test .`** — the bare `.` ignores
  `[test] directory` and sweeps `internal/`.
- **Anything cached off `root` needs a `_reset_<x>_cache_for_tests()` hook** called at the top of
  each test. `jid(root)` is identical across tests sharing a worker, so keying the cache does not
  give you isolation.

## What a passing `jac test` does not prove

Two failure classes are invisible to it. Claiming "tests pass, it works" on either is wrong.

- **Multi-user correctness.** Verified against a single `root` is not verified. A cache leak here
  passed 13 tests and still served one user's node to another, because no test used two `root`s.
  Anything `root`-scoped needs a real two-user test — `JacTestClient`, `register_user`/`login`; see
  `internal/service-registry-spike/tests/multiuser_tests.jac`. This is the standing exception to
  rule 6.
- **Anything client-side.** `jac check` and `jac test` never compile or exercise the client bundle,
  so jac2js miscompiles, broken RPC route names and dead event wiring all pass cleanly. Client and
  UI changes need a live `jac browse` pass. Stop the dev server and clear ports 8000/8001 after.

## Don't test the library

We reuse Monaco, xterm, Radix and friends because they are already tested. Test *our* glue — the
service, the state transition, the adapter — not the library's own behavior. A test that only
proves Monaco can set a value is noise.
