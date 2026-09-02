---
id: 2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure
date: 2026-09-02
category: compiler-bug
severity: major
status: workaround-found
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev mode, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [python-interop, compiler, subprocess, ai-tool-integration, claude-agent-sdk]
---

Found while scoping Phase 5's native Claude Code integration (`architecture.md`'s "AI coding tool
integrations" section), before writing any real `ChatProvider` code -- a live spike, same
discipline `dap_client.jac`'s own docstring already establishes for `debugpy`.

## What happened

A throwaway diagnostic module (`src/workbench/ai/_isolation_probe.jac`, since deleted) did
`import from claude_agent_sdk { query, ClaudeAgentOptions }` at ordinary `.jac` module scope --
the same shape every other server-side import in this codebase uses. Wired into `main.jac` the
same way `run_in_terminal`/`start_debug_session` register their SSE routes (a top-level import in
the entry module -- see `main.jac`'s own comment on why that's needed at all). Running `jac run
--no-client` against this produced **882 real compiler errors**, not a handful -- e.g.:

```
✖ Error: error[E0076]: Duplicate method 'get' in class body
  --> .jac/venv/lib/python3.14/site-packages/httpx2/_models.py:245:4
✖ Error: error[E1053]: Cannot assign Callable[[MCPServer[<any>]], AbstractAsyncContextManager[<any>]] | NoneType to parameter 'lifespan' ...
  --> .jac/venv/lib/python3.14/site-packages/mcp/server/mcpserver/server.py:224:45
```

Unique files affected: `httpx2/_models.py`, `truststore/_api.py`, `click/_termui_impl.py`,
`click/core.py`, `click/types.py`, `cryptography/.../ciphers/base.py`, `mcp/client/client.py`,
`mcp/client/session.py`, `mcp/server/mcpserver/server.py`, `pydantic/json_schema.py` -- every one
of `claude-agent-sdk`'s own transitive dependencies, not `claude_agent_sdk`'s own source. The
server failed to start at all; `jac run` exited without ever reaching "Server ready."

**Root cause (inferred from the evidence, not confirmed against jaclang's own source)**: importing
a Python package at `.jac` module scope makes the compiler eagerly walk and type-check that
package's entire transitive import closure, not just the package's own public surface. A small,
self-contained dependency (`debugpy`, no meaningful runtime deps of its own) never hits this;
`claude-agent-sdk` pulls in `mcp` -> `pydantic`/`httpx2`/`truststore`/`click`/`cryptography`, and
several of those use ordinary, valid Python patterns (conditional method definitions under
`TYPE_CHECKING`, `from __future__ import annotations` forward refs) that the checker's
Python-interop analysis doesn't handle, producing real, if spurious, errors that abort the whole
compile -- not a graceful "treat this import as an opaque boundary" fallback.

## Why this was hard to see coming

`dap_client.jac` never does `import debugpy` at module scope -- it only ever spawns
`python -m debugpy` as a subprocess (see that module's own docstring). It reads, in hindsight, as
if this were a deliberate design choice specific to `debugpy`'s own needs (embedded-interpreter
resolution, the `attach`/`initialized` handshake quirk). It is also, apparently, load-bearing for
a completely different reason that was never stated: **any Python package with a non-trivial
transitive dependency closure cannot be imported into `.jac`-compiled code at all**, full stop --
not a style preference, a hard compiler limit. Nothing in `architecture.md`'s Process Execution
section or `dap_client.jac`'s own docstring says this explicitly; a future contributor reading
only "spawn the subprocess" without this entry could reasonably conclude it was an arbitrary
choice and try a direct import for a different tool, and hit the same 882-error wall.

## The fix

Never `import` a third-party Python package with any real dependency closure directly into `.jac`
module code. Drive it from a plain `.py` launcher script (this project's own precedent:
`src/workbench/dap/dap_launcher.py`), spawned as a subprocess via
`asyncio.create_subprocess_exec`, with results relayed back over stdout (newline-delimited JSON,
matching this project's existing SSE-event convention) -- never imported into the `.jac` process
itself. Confirmed working end-to-end once fixed: a subprocess-only launcher (never importing
`claude_agent_sdk` from `.jac` code) compiled clean (0 errors) and streamed real
`SystemMessage -> AssistantMessage -> RateLimitEvent -> ResultMessage` events back through a real
`jac run` SSE endpoint.

A second, smaller finding surfaced fixing this: the subprocess also needs `PYTHONPATH` built from
the *running server's own* `sys.path` (which includes `.jac/venv/lib/python3.14/site-packages`,
where `jac install` actually puts `[dependencies]`-declared packages) -- `_resolve_embedded_python`
's target interpreter (the shared `~/.cache/jac/rt/<hash>/python` runtime cache) has none of this
project's own dependencies installed on its own. This isn't new -- `dap_client.jac`'s own
`_build_pythonpath` already does exactly this, for the same reason -- but it's easy to omit by
accident when writing a new subprocess-based client from scratch (this spike did, on the first
pass), and the failure mode (`ModuleNotFoundError` inside the spawned subprocess) looks identical
to "the package isn't installed at all," which it isn't.

## Plan

The permanent-correct practice (subprocess-only, never a direct `.jac`-scope import, for any
non-trivial Python dependency) is now confirmed and should be treated as a hard rule for Phase 5's
real `ChatProvider`/`InlineCompletionProvider` work, not just a recommendation -- add it explicitly
to `docs/architecture.md`'s Process Execution or AI coding tool integrations section so it's
written down before more than one person needs to rediscover it.

Whether the *root cause* (the compiler eagerly type-checking an imported Python package's full
transitive closure instead of treating third-party imports as an opaque interop boundary) is worth
reporting upstream to jaseci is open -- this entry documents the observed behavior and a working
project-level practice around it, not a confirmed jaclang defect with a minimal repro isolated from
this project's own dependency tree. A future attempt to report it upstream should start by trying
to reproduce the failure with a minimal synthetic package (a small package that itself imports
something using `TYPE_CHECKING`-conditional method definitions) rather than the full
`claude-agent-sdk` closure, to isolate exactly which Python pattern trips the checker.
