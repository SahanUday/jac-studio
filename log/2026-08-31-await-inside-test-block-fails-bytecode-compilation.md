---
id: 2026-08-31-await-inside-test-block-fails-bytecode-compilation
date: 2026-08-31
category: compiler-bug
severity: major
status: workaround-found
phase: 4
subsystem: tooling
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jaseci, asyncio, testing, jac-test, bytecode-compilation, type-checker]
---

## What happened

Writing tests for the new LSP client (`src/workbench/lsp/lsp_client.jac`, the first server-side
module in this project with several `async def` functions that internally `await` each other, not
just one like `terminal_service.jac`'s single un-tested `run_in_terminal`), the most basic possible
test -- `await`ing an already-working `async def:pub` function from inside a `test` block -- failed
to even *import* under `jac test`, despite `jac check` accepting the identical code with zero
errors.

## Bug 1: a literal `await` inside a `test` block never compiles to real async bytecode

Reproduced down to the minimal possible case -- a `test` block awaiting nothing but a bare
`asyncio.sleep(...)`, no wrapping function at all:

```jac
import asyncio;

test "bare await inside a test block" {
    await asyncio.sleep(0.01);
    assert True;
}
```

```
jaclang.meta_importer.JacSourceCompileError: ... failed to compile:
error[E5043]: Bytecode compilation failed: 'await' outside async function
```

`jac check` on the identical file reports zero errors. Confirmed this isn't about `:pub`, argument
count, return type, or how deeply the `await` is nested through helper functions -- every variant
tried (a private `async def` with no params, a `def:pub` version, a version taking an argument, a
two-level `async def` calling another `async def`) fails the exact same way, and the failure is
triggered specifically by the literal `await` keyword appearing anywhere inside the `test` block's
own body, not by anything about the function(s) it calls.

Cross-checked against real, already-shipped, already-live-verified code: `terminal_service.jac`'s
`run_in_terminal` is `async def:pub` with an internal `await`, and it works correctly when actually
served (`jac run --serve --dev`, exercised via the integrated terminal across several earlier PRs)
-- so this is specifically a `jac test`/import-hook bytecode-compilation gap
(`jaclang/meta_importer.py`'s `exec_module`), not a general problem with async functions at
runtime. It just happens that `run_in_terminal` was the *only* server-side async function in this
project before now, and it has no test file -- previously assumed to be "gated feature, hard to
unit test," but this finding shows it's also **impossible** to unit test today, not just impractical.

### Workaround

`asyncio.run(some_async_call())`, called as a plain synchronous expression with **no `await`
keyword anywhere in the test block**, correctly drives the same async code end to end and sidesteps
the bug entirely -- confirmed for both a single async function and a nested async-calls-async
chain.

## Bug 2 (separate, found while building the workaround): `asyncio.run()` on an annex/cross-module async call infers the wrong type

`asyncio.run(_read_message(stream))`, where `_read_message` is an `async def:pub` in the paired
module this `.test.jac` annex belongs to (so reachable via annex scope, not an explicit `import
from`), fails `jac check` itself:

```
error[E1053]: Cannot assign dict[str, Any] | NoneType to parameter 'main' of type Coroutine[Any, Any, _T]
```

The checker is inferring the call expression's type as `_read_message`'s plain declared return type
(as if it had already been `await`-ed), not `Coroutine[Any, Any, dict[str, Any] | None]` -- the
actual type `asyncio.run` needs. Reproduced the same way with a real cross-module `import from`
(a separate `subpkg.mod_a` test package, not just the annex case) -- same error, so this isn't
specific to annex scoping either. The *identical* pattern against a function defined in the *same*
file the `asyncio.run(...)` call lives in type-checks and runs correctly -- the bug is specifically
in how the checker infers an async call's type across a module/annex boundary.

### Workaround

Wrap the cross-module/annex call in a tiny local `async def` (defined in the same file as the
`asyncio.run(...)` call) that just `await`s it and returns the result, then `asyncio.run()` *that*
local wrapper instead. The checker infers a locally-defined async function's call-site type
correctly; only the cross-boundary case is wrong.

```jac
async def _wrap_read_message(stream: any) -> dict[str, any] | None {
    return await _read_message(stream);
}

test "..." {
    parsed = asyncio.run(_wrap_read_message(stream));
    ...
}
```

## Plan

Both workarounds are cheap and now applied in `lsp_client.test.jac` -- not a blocker for this PR.
But this is a real gap worth a proper upstream report: **no server-side module with an `async
def` that internally `await`s another call could be meaningfully unit-tested before this session
found the workaround**, and the second bug means even the workaround needs an extra wrapper
function whenever the async call crosses a module/annex boundary, which is the *normal* shape for
testing anything beyond a single-file toy. Worth flagging to the jaseci team directly (or filing
upstream) rather than leaving this to be independently re-discovered by the next session that tries
to unit-test async server code -- the DAP client (later in this same phase) is the next near-certain
candidate to hit both of these.
