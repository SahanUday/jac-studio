---
id: 2026-09-22-jac-run-takeover-spawns-competing-dev-server-from-a-nested-project-less-directory
date: 2026-09-22
category: ergonomics
severity: major
status: workaround
phase: 7
subsystem: workbench-shell
jac_version: "0.37.3"
related_vscode_ref: ""
upstream_issue: ""
tags: [cli, jac-run, takeover, terminal, dev-server]
---

Found live via the new real-PTY terminal (ADR 0078): a real user ran `jac run hello.jac` from
inside `testing-workspace/` (jac-studio's own gitignored fixture, a subdirectory of the jac-studio
checkout with no `jac.toml` of its own) expecting it to just execute the script. Instead it printed:

```
jac run: takeover: hello.jac runs as the project 'jac-studio' at /home/sahan/dev/vs/jac-studio,
rewriting its client build (--no-takeover runs it standalone)
```

...and spawned a **second, fully separate `jac run --dev` instance** — its own vite/bun dev server
on a freshly-picked port (8007 in the first occurrence, 8003/8005/8006 on repeat attempts) — as a
side effect of a command that looked like it should just print a calculator's output. Confirmed
live and reproduced directly (`jac run --show hello.jac` from `testing-workspace/`):

```
project kind : web-app
action       : serve
summary      : Serve full-stack app with client (dev mode)
entry-point  : /home/sahan/dev/vs/jac-studio/testing-workspace/hello.jac
equivalent   : jac run hello.jac --dev
```

Root cause: `jac run <file>` walks up from the file's directory looking for the nearest
`jac.toml`; a project-less subdirectory of a real project (exactly what a "workspace fixture
nested inside the tool's own repo" is) resolves to the **outer** project's `jac.toml` and "takes
over" running as that project instead of standalone. Each retry left its dev server running
(discovered three orphaned instances, ports 8003/8005/8006-8007, accumulated across the user's
several attempts — each consuming real memory and a port, with no obvious signal to the user that
anything beyond "run this script" had happened).

This isn't new CLI behavior this milestone introduced — `--no-takeover` is a documented,
already-existing escape hatch, and the message itself explains what happened. What's new is that
the real PTY terminal (replacing the old one-shot-subprocess model) makes running arbitrary shell
commands, including plain `jac run <file>`, a completely natural, expected action inside
jac-studio's own terminal panel for the first time — so a footgun that previously required
deliberately invoking the CLI from a real shell is now one keystroke away inside the product
itself, and easy to trigger repeatedly without noticing (each attempt silently leaves another
server running rather than failing loudly).

## Plan

Not a bug in `jac run`'s own logic — the takeover behavior is deliberate and documented. Two things
worth doing:

1. **Immediate, permanent fix for this fixture specifically**: give `testing-workspace/` its own
   minimal `jac.toml` (`[project] name = "testing-workspace"`, no `kind` — inferred as `cli` since
   its files are plain scripts). Verified live: `jac run hello.jac` then resolves to
   `project kind: cli / action: execute`, no takeover, no server spawned. Since `testing-workspace/`
   is gitignored (its own git state is the fixture), this file isn't part of any PR — it's local
   state for whoever's running the fixture, and worth calling out in
   `jac-studio-git-workflow`'s testing-workspace section so it isn't rediscovered per-machine.
2. **Worth raising upstream**: the takeover default is a genuine footgun specifically for the
   "example/test file living in a project-less subdirectory of a real project" shape — silently
   consuming a port and a real dev-server process's worth of memory on every retry, with no count
   or warning that N of these have now accumulated, is a bad default for that shape even though the
   message technically explains itself. A louder warning (or refusing to re-spawn if an
   already-running takeover instance for the same entry-point is detected) would have caught this
   on the second attempt, not left three orphaned processes to be found by hand.
