---
id: 2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source
date: 2026-08-31
category: missing-feature
severity: minor
status: workaround
phase: 4
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: "src/vs/workbench/contrib/debug/"
upstream_issue: ""
tags: [dap, debugger, debugpy, jac-lsp-precedent]
---

`docs/architecture.md` and `docs/roadmap.md` both flagged the Phase 4 DAP client as needing its
own research spike before design, with two explicit open sub-questions: does jaclang ship a debug
adapter (the same way it ships a real LSP server behind `jac lsp`), and is a Python DAP
client/server library usable via interop. Answered both empirically before starting
implementation.

**No Jac-native DAP server exists.** `jac run --debug` only wires up
`jaclang/runtime/debugger.jac`'s `Jdb(pdb.Pdb)` — a bare `pdb` subclass driven over plain stdio
(`jaclang/cli/commands/impl/execution.impl.jac:1117-1149`, `db.runcall(func)`), not a JSON-RPC/DAP
server. Zero hits anywhere in `/home/sahan/dev/jaseci` for `debugpy`/`debug_adapter`/
`DebugAdapter`/`adapter_protocol`. VS Code integration is documented (`jac guide reference/cli`,
a `"type": "jac"` launch config with breakpoints/stepping/the `jacvis` graph visualizer), but
that bridge lives in a separate, not-checked-out-here repo (`jaseci-labs/jac-vscode`), not in
jaclang itself.

**`debugpy` works directly against jaclang-compiled bytecode, unmodified — confirmed with a full
DAP round trip, not just a theory.** The key fact: `JacProgram().compile(<file>.jac).gen.py_bytecode`
already carries a code object whose `co_filename` is the literal `.jac` path and whose line table
maps 1:1 to real `.jac` source lines (verified via `code.co_lines()` — this is what already makes
`Jdb`'s plain-pdb breakpoints work at `.jac` granularity, not a coincidence). Since both `pdb` and
`debugpy`/pydevd resolve breakpoints purely via `frame.f_code.co_filename` + `frame.f_lineno` +
`sys.settrace`, the same mechanism carries over cleanly to a real DAP adapter with zero source
translation needed.

Full working recipe, spiked end-to-end against `hello.jac` (a top-level function called from
`with entry:__main__`):
1. A tiny launcher shim (plain `.py`, not `.jac`) does `JacProgram().compile(fname)`,
   `marshal.loads(bytecode)`, wraps it `types.FunctionType(code, {"__name__": "__main__"})`, and
   calls it.
2. Spawn `<embedded-python> -m debugpy --listen <host:port> --wait-for-client <shim>.py <file.jac>`
   as a subprocess — **must use the actual embedded Python binary**
   (`sys.prefix`'s `bin/python3.14` under `~/.cache/jac/rt/<hash>/python/`), not `sys.executable`
   from inside a running `jac run` process (that resolves to the `jac` zig binary itself, which
   debugpy's own internal adapter-spawn logic can't invoke — confirmed by reproducing the failure:
   `error: argument COMMAND: invalid choice: '.../debugpy/adapter'`).
3. Set `PYTHONPATH` for that subprocess to jaclang's own resolution path
   (`/home/sahan/dev/jaseci/jac` + the runtime's `.../rt/<hash>/site` dir — read these from
   `sys.path` inside an ordinary `jac run` process) so the shim's `import jaclang...` resolves;
   without it the shim dies with a plain `ModuleNotFoundError: No module named 'jaclang'`.
4. Speak standard DAP JSON-RPC-over-TCP (Content-Length framed) to the adapter. One real
   debugpy-specific ordering quirk, confirmed by reading `debugpy/adapter/clients.py:250-282`
   directly: **debugpy sends the `initialized` event as part of handling the `attach`/`launch`
   request, not immediately after responding to `initialize`** (its own comment even flags this as
   non-strict-DAP-spec behavior it deliberately keeps for pydevd compatibility) — a client that
   waits for `initialized` before sending `attach` deadlocks. Send `attach` first, then wait for
   `initialized`.
5. Verified: `setBreakpoints` on `hello.jac:5` came back `verified: true`; a `stopped` event fired
   with `reason: "breakpoint"`; `stackTrace` showed frame name `add` at `hello.jac` line 5 with the
   real absolute `.jac` path as `source.path`; `variables` returned real Jac identifier names and
   live values (`a: 2`, `b: 3`, `total: 5`) — not transpiled/mangled Python names, not a Python
   fallback file.

**Plan**: build the DAP client against this recipe, targeting real `.jac` source-level debugging
directly (not a Python-only fallback) — the spike closes the "is this even possible" question the
docs flagged as unresolved. Concretely: (1) a generic client module speaking DAP over TCP to a
spawned `debugpy --listen` adapter, mirroring the LSP client's subprocess-management shape: (2) the
launcher-shim script becomes a small first-party file the DAP client spawns debugpy against, not a
one-off spike script; (3) `PYTHONPATH`/embedded-interpreter-path resolution needs to be derived
generically (not hardcoded to this machine's cache hash) — likely by having the walker that spawns
the subprocess inherit the same `sys.path`/`sys.prefix` values visible from inside the running
`jac`-served process, the same way it already knows how to spawn other subprocesses; (4) `debugpy`
becomes a new Python dependency the project needs to install into its own managed runtime, not
just this spike's ad hoc `uv pip install --python <embedded interpreter>`; (5) this only proves the
single-function, single-thread case — multi-frame call stacks across `walker`/`node`/`edge`
archetype methods, and whatever `root`/graph-bound execution looks like under a live `jac run
--serve` session (rather than a bare script), are real follow-on unknowns the actual
implementation still needs to verify, not covered by this spike.
