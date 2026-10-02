---
id: 2026-10-02-jac-fix-dependencies-blocked-by-the-manifest-it-migrates
date: 2026-10-02
category: compiler-bug
severity: major
status: upstream-tracked
phase: 8
subsystem: tooling
jac_version: "0.37.24 (jaseci main @a92b8131a, dev build)"
related_vscode_ref: ""
upstream_issue: "jaseci-labs/jac#9698"
tags: [jac-fix, jac-toml, dependencies, migration]
---

Bumping `jac` to `0.37.24` makes `[dependencies]` list Jac packages only; Python packages must move
to `[dependencies.pypi]`. A manifest that still has them fails to load, and the documented
migration, `jac fix dependencies`, hits the same load error and exits 2 before it can run. No
supported path exists from a legacy `jac.toml` to a valid one.

Repro (two-line `jac.toml` with `requests = ">=2.0"` under `[dependencies]`): `jac fix dependencies
--dry-run` prints `jac.toml is invalid: ... lists requests, which are not Jac packages` and exits 2.
Cause: the CLI dispatcher validates the manifest before every command, `fix` included; the
migration's own tests call `migrate_manifest` directly and never go through the CLI.

**Plan**: Filed upstream ([jaseci-labs/jac#9698](https://github.com/jaseci-labs/jac/issues/9698))
with a root cause and a fix: `fix` tolerates an invalid manifest during discovery. The fix plus a
subprocess regression test sit on the local jaseci branch
`fix/fix-dependencies-blocked-by-invalid-manifest` (9a7459da3); jac-studio's root `jac.toml` was
migrated with that patched compiler. No hand-edit of the manifest was needed or used. Once the fix
ships in a release, the patched compiler is no longer required for this migration.
