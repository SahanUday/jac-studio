"""TerminalService: server-side process execution backing the integrated terminal.
Deny-by-default, gated by `[terminal] enabled` in `jac.toml`. See ADR 0025.
One-shot spawn per call, no persistent shell session -- `cd`/env vars don't persist. See ADR 0026.
Declared `async def:pub`, not sync: jaclang's SSE dispatcher only thread-offloads a sync
generator's *first* call, so later `readline()`s would block the event loop for every request."""

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

"""Spawns `command` in a shell, streaming combined stdout/stderr one line at a time."""
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
