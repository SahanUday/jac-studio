---
id: 2026-08-28-jac-db-cli-wrong-database-multiple-top-level-jac-files
date: 2026-08-28
category: compiler-bug
severity: minor
status: open
phase: 3
subsystem: tooling
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [cli, jac-db, tooling]
---

## What happened

Found while root-causing `2026-08-28-field-mutation-on-cached-node-not-persisted`: `jac db sql`,
`jac db inspect`, and `jac db status` (run with no explicit database name, the normal invocation
from a project's own root) silently connect to the *wrong*, unrelated, empty database once the
project's root directory has more than one top-level `.jac` file.

`jaclang/cli/commands/impl/db.impl.jac`'s `_project_database()` infers which project a bare
`jac db ...` invocation means by globbing `Path.cwd()` for `*.jac` files and using the single match
as the target passed to `project_db_name(base, target)`:

```jac
def _project_database -> str {
    import from jaclang.runtimelib.session { project_db_name }
    base = str(Path.cwd());
    jacs = sorted(p for p in Path.cwd().glob("*.jac") if p.is_file());
    target = str(jacs[0]) if len(jacs) == 1 else None;
    return project_db_name(base, target);
}
```

`len(jacs) == 1` silently falls back to `target = None` the moment a second top-level `.jac` file
exists — with no warning that the detection became ambiguous. `jac-studio`'s root has had exactly
this shape since PR #35 (`main.jac` + `main.impl.jac`, the documented "client component handler
annex" pattern from `jac-studio-code-organization`, itself following an established jaseci-source
convention). Running `jac db sql "SELECT count(*) FROM anchors"` from the project root reported `0`
rows — not an error, a plausible-looking empty result — because it silently resolved to
`jac_main_<hash>` instead of the real, live `jac_jac_studio_<hash>` database `jac run --serve`
itself connects to (confirmed via `jac db list`, which enumerates by owner path rather than this
same globbing logic, and does correctly show the real database as `live`).

The actual `jac run --serve`/`jac run --serve --dev` **server process is unaffected** — it's given
an explicit entry file (`jac run --serve --dev main.jac`), so it doesn't go through this
directory-globbing inference at all. Only the standalone `jac db <action>` diagnostic commands,
invoked bare from a project root, are affected.

## Plan

Not a jac-studio bug — this is jaseci CLI behavior, and jac-studio's `main.impl.jac` file is a
correct, intentional application of this project's own documented code-organization convention;
renaming or removing it to work around the CLI's detection gap would be exactly backwards. The real
fix belongs upstream: `_project_database()` should prefer `entry-point` from the project's own
`jac.toml` over re-deriving a target by globbing the directory, since `jac.toml` already
unambiguously names the entry file the *server* itself uses — falling back to the directory glob
only when no `jac.toml`/`entry-point` is present (a bare script directory with no project file).
Until then, the practical workaround for inspecting this project's actual data is to bypass
`_project_database()`'s inference entirely: run a throwaway `.jac` script (from any cwd, with its
own minimal `jac.toml`) that imports `jaclang.runtimelib.pgembed.PgRuntime` /
`jaclang.runtimelib.store.PgStore` directly and passes the real database name explicitly (read from
`jac db list`'s output, e.g. `jac_jac_studio_4ece06b5`), rather than relying on any `jac db`
subcommand's own name inference from the project directory.
