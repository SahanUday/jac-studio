"""ClaudeCodeClient: Phase 5's native Claude Code integration (`docs/roadmap.md`'s "native AI
coding-tool integrations" phase, `docs/architecture.md`'s "AI coding tool integrations" section) --
the first of the three named tools (Copilot, OpenCode, Claude Code), chosen first because its
integration surface (the `claude-agent-sdk` PyPI package) is the best-documented and needed no
open research question to confirm, unlike the other two.

**Never `import claude_agent_sdk` here or anywhere else in `.jac`-compiled code.** Confirmed live
(tracker entry 2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure):
doing so makes the compiler eagerly type-check the SDK's entire transitive dependency closure (mcp,
pydantic, httpx2, truststore, click) and fail with hundreds of real errors, aborting the whole
server build. `claude_code_launcher.py` (this module's sibling, plain Python, not Jac) is the only
place that ever imports the SDK -- the same shape `dap_launcher.py` already established for
`debugpy`, confirmed here to be load-bearing for a second, previously-unstated reason (that import
explosion), not just a stylistic echo of the DAP client.

**Gated behind the same `[terminal] enabled` flag as the terminal, `jac lsp`, and the DAP client,
for the identical reason** -- spawning `claude_code_launcher.py` is a subprocess execution, the
same trust class already gated project-wide.

**`cwd` is set to the actual open workspace root, not wherever this server process happens to
run.** Confirmed live during the isolation spike this module is built on: without an explicit
`cwd`, the SDK inherits the *server process's* cwd, which pulled in jac-studio's own `.claude/`
config (hooks fired, this project's own skills/agents listed) instead of the user's actual open
project -- the same per-project scoping real Claude Code already does, but something this client
has to set deliberately rather than get by accident.

**`PYTHONPATH` is built from this running process's own `sys.path`, mirroring
`dap_client.jac`'s `_build_pythonpath`.** `_resolve_embedded_python`'s target (the shared
`~/.cache/jac/rt/<hash>/python` runtime cache) has none of this project's own `[dependencies]`
installed on its own -- those land in `.jac/venv` via `jac install`, a different location. Without
this, the spawned launcher fails with `ModuleNotFoundError: No module named 'claude_agent_sdk'`
even though the package is genuinely installed (confirmed live, same spike).

**No mid-session cancel in this first slice, deliberately.** Unlike a debug session (indefinitely
running, needs continue/step control while live), a chat turn is a single `query()` call that
naturally ends on its own -- there's no equivalent of DAP's `_DAP_COMMAND_FILE` control channel
needed here, and the still-open question in tracker entry
2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run (whether a
Generator-returning SSE endpoint really is isolated from other calls in this codebase, contradicting
`dap_client.jac`'s own finding) is sidestepped entirely rather than relied on either way. A "stop
generating" control is real, legitimate future work, not silently dropped -- it would need the same
file-based command channel `dap_client.jac` already established, once actually needed.

**Multi-turn conversation is session-resumption, not a persistent connection.** Each user message
is one `start_chat_turn` call; passing the previous turn's `session_id` back in as `resume` is the
SDK's own documented mechanism for conversation continuity (`docs/en/authentication`'s and
`docs/en/agent-sdk/streaming-output`'s own `session_id` field on every message) -- no long-lived
subprocess or connection needs to survive between turns.

**`approve_tool_call` is an ordinary RPC stub, not part of the stream -- the same shape
`dap_client.jac`'s `continue_execution`/`step_over`/... take, for the identical reason.** A tool
call awaiting approval lives inside `claude_code_launcher.py`'s own process (see that module's own
docstring), a process this RPC call has no shared memory with -- it reaches the live wait purely
via `_TOOL_APPROVAL_FILE`, a fixed `/tmp` path both sides agree on without needing to ask each
other. See the launcher's own docstring for why `/tmp` is hardcoded rather than derived."""

import asyncio;
import glob as glob_module;
import json;
import os;
import sys;
import from typing { AsyncGenerator, Generator }
import from jaclang.project.config { JacConfig }
import from src.workbench.workspace.workspace_service { get_current_workspace }

def _ai_enabled -> bool {
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

"""Picks the embedded runtime's own Python binary from a list of glob-matched candidates -- the
same small, independently-testable helper `dap_client.jac`'s own `_pick_python_binary` establishes;
duplicated here rather than imported since it's `_`-prefixed (internal to its own module) in both
places. Worth extracting into a shared helper module if a third client ever needs it."""
def:pub _pick_python_binary(candidates: list[str]) -> str | None {
    if len(candidates) == 0 {
        return None;
    }
    return sorted(candidates)[0];
}

def _resolve_embedded_python -> str | None {
    pattern = os.path.join(sys.prefix, "bin", "python3*");
    return _pick_python_binary(glob_module.`glob(pattern));
}

"""Joins `path_entries` (the caller's own `sys.path`) into a `PYTHONPATH` string, dropping empty
entries. Same shape as `dap_client.jac`'s `_build_pythonpath`, duplicated for the same reason as
`_pick_python_binary` above."""
def:pub _build_pythonpath(path_entries: list[str]) -> str {
    entries = [p for p in path_entries if p];
    return os.pathsep.join(entries);
}

def _launcher_path -> str {
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude_code_launcher.py");
}

"""The one SSE-streamed entry point. Spawns `claude_code_launcher.py` with `prompt` (and `resume`
if `session_id` continues an existing conversation), relays each JSON event line it prints as an
SSE frame unchanged (the launcher already emits the shape the client needs -- see its own
docstring), and ends the stream once the subprocess exits. Refuses to run at all when
`[terminal] enabled = false`, matching `dap_client.jac`'s `start_debug_session` and
`lsp_client.jac`'s equivalent gate exactly."""
async def:pub start_chat_turn(prompt: str, session_id: str | None) -> Generator {
    async def stream -> AsyncGenerator[str, None] {
        if not _ai_enabled() {
            yield json.dumps({"type": "error", "message": "AI tool integrations are disabled. Set [terminal] enabled = true in jac.toml to turn them on."});
            return;
        }

        python_bin = _resolve_embedded_python();
        if python_bin is None {
            yield json.dumps({"type": "error", "message": "No Python interpreter found for the embedded Jac runtime."});
            return;
        }

        ws = get_current_workspace();
        cwd = ws["root_path"] if ws is not None else None;

        env = dict(os.environ);
        env["PYTHONPATH"] = _build_pythonpath(sys.path);

        args = [python_bin, _launcher_path(), prompt];
        if session_id {
            args.append("--resume");
            args.append(session_id);
        }
        if cwd {
            args.append("--cwd");
            args.append(cwd);
        }

        try {
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                env=env
            );
        } except Exception {
            yield json.dumps({"type": "error", "message": "Failed to spawn the Claude Code launcher process."});
            return;
        }

        stdout = proc.stdout;
        while stdout is not None {
            line = await stdout.readline();
            if not line {
                break;
            }
            text = line.decode("utf-8", errors="replace").strip();
            if not text {
                continue;
            }
            try {
                json.loads(text);
                yield text;
            } except Exception {
                # A non-JSON stdout line means the SDK/launcher crashed before emitting a real
                # event (an uncaught exception's traceback, an import error) rather than a
                # malformed real event -- surfaced as a real error event, not silently dropped.
                yield json.dumps({"type": "error", "message": text});
            }
        }
        await proc.`wait();
    }
    report stream();
}

glob _TOOL_APPROVAL_FILE: str = "/tmp/jac_studio_tool_approval_decisions.json";

"""Records the user's approve/deny decision for one tool call so
`claude_code_launcher.py`'s `can_use_tool` callback -- polling the same fixed path from a
genuinely separate process, see this module's own docstring -- picks it up on its next poll.
`decision` is `"allow"` or `"deny"`; anything else is stored as-is and reads back as an implicit
deny (the launcher only ever treats the literal string `"allow"` as approval)."""
async def:pub approve_tool_call(tool_use_id: str, decision: str) -> None {
    if not _ai_enabled() {
        return;
    }
    decisions: dict[str, str] = {};
    try {
        if os.path.exists(_TOOL_APPROVAL_FILE) {
            with open(_TOOL_APPROVAL_FILE, "r") as f {
                decisions = json.load(f).get("decisions", {});
            }
        }
    } except Exception {}
    decisions[tool_use_id] = decision;
    tmp_path = _TOOL_APPROVAL_FILE + ".tmp";
    with open(tmp_path, "w") as f {
        json.dump({"decisions": decisions}, f);
    }
    os.replace(tmp_path, _TOOL_APPROVAL_FILE);
}
