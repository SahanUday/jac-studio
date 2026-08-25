"""TerminalService: server-side process execution backing the integrated terminal
(`docs/roadmap.md` Phase 2, per `docs/architecture.md`'s Process Execution section). Deny-by-default,
gated by a `[terminal]` section in `jac.toml` -- `enabled = true` must be set explicitly, mirroring
architecture.md's reasoning for the `@jac/desktop` `shell` capability ("safe... same trust level as
[the user] opening their own terminal") even though jac-studio ships as a `web-app` kind project
(`jac.toml`'s `[project] kind`), not a packaged desktop app, so that capability plugin isn't
reachable here -- `JacConfig.get_section` reads jac-studio's own `[terminal]` section directly
instead of going through `@jac/desktop`.

**Streamed via a live async generator, not `subprocess.run`+`readline()` in a sync generator.**
jaclang's SSE dispatcher only offloads a *sync* `def:pub`'s initial call onto a worker thread
(`asyncio.to_thread`, `jaclang/runtimelib/serving/app.jac`) to get the generator object -- every
subsequent `next()` on that generator (i.e. every blocking `readline()`) then runs directly on the
event loop (`_sse_frame_stream_inner`'s plain `for item in source` in
`jaclang/runtimelib/serving/sse.jac`), stalling every other concurrent request for the whole
process's runtime. Declaring this `async def:pub` instead means the dispatcher `await`s it directly,
and `sse_frame_stream` drives an async generator with `async for` -- so
`asyncio.create_subprocess_shell` + `await process.stdout.readline()` yields control back to the
loop between lines like any other async I/O wait, instead of blocking it.

**One-shot spawn per call, not a persistent shell session (2026-08-25 v1 scope).** A real OS
terminal keeps one long-lived shell process alive so `cd`/exported env vars/interactive REPLs
persist across commands. That needs a server-side session keyed by an id, with input written to a
held-open process's stdin from a *second* endpoint while its stdout is still being streamed from the
first -- a meaningfully bigger, session-lifecycle-managing feature (holding OS handles open across
requests, cleaning them up if the tab closes) than "spawn a process, stream its output" calls for.
Deferred the same way the command palette deferred keybinding scoping to its own roadmap bullet --
`run_in_terminal` spawns and streams exactly one independent process per call, so `cd` doesn't
persist between commands typed into the terminal. Worth a dedicated follow-up if this bites in
practice.
"""

import asyncio;
import from typing { AsyncGenerator, Generator }
import from jaclang.project.config { JacConfig }

def _terminal_enabled -> bool {
    cfg = JacConfig.discover();
    if not cfg {
        return False;
    }
    section = cfg.get_section("terminal");
    if not section {
        return False;
    }
    return bool(section.get("enabled", False));
}

"""Spawns `command` in a shell and streams its combined stdout/stderr back one line at a time,
ending with an `[process exited with code N]` line. Refuses to run anything when `[terminal]
enabled` isn't set in `jac.toml` -- deny-by-default, the same posture `docs/architecture.md` scopes
for the desktop `shell` capability."""
async def:pub run_in_terminal(command: str, cwd: str) -> Generator {
    async def stream -> AsyncGenerator[str, None] {
        if not _terminal_enabled() {
            yield "Terminal is disabled. Set [terminal] enabled = true in jac.toml to turn it on.\n";
            return;
        }
        if not command.strip() {
            return;
        }
        try {
            process = await asyncio.create_subprocess_shell(
                command,
                cwd=cwd if cwd else None,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT
            );
        } except Exception as e {
            yield f"Failed to start command: {e}\n";
            return;
        }
        stdout = process.stdout;
        if stdout is None {
            yield "Failed to start command: no stdout pipe.\n";
            return;
        }
        while True {
            line = await stdout.readline();
            if not line {
                break;
            }
            yield line.decode("utf-8", errors="replace");
        }
        await process.`wait();
        yield f"\n[process exited with code {process.returncode}]\n";
    }
    report stream();
}
