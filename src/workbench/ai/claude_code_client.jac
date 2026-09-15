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

**`cwd` is resolved by the *caller*, outside the SSE generator, and passed in as a plain
argument -- never queried from inside `stream()` itself.** An earlier version called
`get_current_workspace()` (a real graph query, `[root-->[?:Workspace]]`) from inside `stream()`,
on the theory that a `Generator`-returning endpoint still sees the same `root`-scoped graph state
as an ordinary call. **Confirmed live, and wrong, via real user reports (not assumed): the same
mechanism produced two distinct failures** -- a first turn silently answered from the *server
process's own* cwd instead of the real open workspace (`get_current_workspace()` returned `None`
inside the generator even though `open_workspace` had genuinely succeeded moments earlier in the
same browser session), and a second turn in the same session hit a real
`PgWireError: connection lost mid-transaction; retry` at that exact call site. Both are one root
cause: the two still-open tracker entries on SSE-generator isolation
(`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`,
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`) only tested plain
`glob` state: this is the first confirmation the same isolation risk extends to a real
`root`-scoped *graph query with its own DB connection/transaction*, not just an in-memory dict --
worth its own tracker entry, see `2026-09-05-sse-generator-root-scoped-graph-query-unreliable`.
**The fix is the exact pattern `2026-09-01-...`'s own Plan section already prescribes for
"state needed only at spawn time": resolve it via an ordinary call, before the generator ever
starts, and pass it in as a function argument.** `ai_chat.jac`/`inline_chat_widget.jac` now call
`get_current_workspace()` themselves (a plain, non-generator RPC call -- the exact same call
`file_tree.jac`'s own session restore already makes successfully) immediately before POSTing to
`start_chat_turn`, and pass the resolved `cwd` in the request body. `stream()` itself no longer
calls `get_current_workspace()` or imports `workspace_service` at all.

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

glob _ATTACHMENT_MAX_CHARS: int = 50000;

"""Builds the text actually sent to the launcher as its one positional `prompt` argument --
`prompt` itself, unchanged, when there are no attachments (the common case, and the only case
before this existed). **`attached_paths`'s content is read and prepended here, server-side, rather
than trusting the model to fetch it itself or hoping the CLI parses some `@file` marker out of raw
text** (real VS Code's own file-attachment picker -- confirmed by reading
`chatDynamicVariables.ts`/`chatAttachmentModel.ts` in a real `microsoft/vscode` checkout before
building this -- works the identical way: a picked file becomes a resolved, real attachment
*before* the request goes out, never a hope that raw inline text gets specially parsed downstream).
`ai_chat.jac`'s own `messages` log still shows the user's original, unaugmented `prompt` -- this
function's output is only what actually reaches the launcher, keeping the visible conversation log
readable regardless of how much file content rides along with it. Each file is capped at
`_ATTACHMENT_MAX_CHARS` (truncated with a visible note, never silently) -- a real guard, not
theoretical: an attached file large enough to blow out a turn's context is a real possibility the
picker itself (`ai_chat.jac`, reusing `workspace_service.jac`'s own `list_all_files`) has no reason
to prevent a user from selecting. A path that can't be read (removed since the picker fetched its
list, a permissions error, ...) gets a visible inline note instead of silently vanishing from the
prompt or aborting the whole turn."""
def _build_prompt_with_attachments(prompt: str, attached_paths: list[str]) -> str {
    if len(attached_paths) == 0 {
        return prompt;
    }
    blocks = [];
    for path in attached_paths {
        name = os.path.basename(path);
        try {
            with open(path, "r", encoding="utf-8", errors="replace") as f {
                content = f.read();
            }
        } except Exception as exc {
            blocks.append(f"--- Attached file: {name} ({path}) ---\n[could not be read: {exc}]");
            continue;
        }
        if len(content) > _ATTACHMENT_MAX_CHARS {
            content = content[:_ATTACHMENT_MAX_CHARS] + "\n[... truncated]";
        }
        blocks.append(f"--- Attached file: {name} ({path}) ---\n{content}\n--- end of {name} ---");
    }
    return "\n\n".join(blocks) + "\n\n" + prompt;
}

"""The one SSE-streamed entry point. Spawns `claude_code_launcher.py` with `prompt` (and `resume`
if `session_id` continues an existing conversation), relays each JSON event line it prints as an
SSE frame unchanged (the launcher already emits the shape the client needs -- see its own
docstring), and ends the stream once the subprocess exits. Refuses to run at all when
`[terminal] enabled = false`, matching `dap_client.jac`'s `start_debug_session` and
`lsp_client.jac`'s equivalent gate exactly.

**`attached_paths`/`model`/`permission_mode`/`effort` (2026-09-04, real-user QA) are the client's
own current picker state, sent fresh on every turn -- not session-level settings resolved here.**
`ai_chat.jac`'s docstring covers the picker UI itself; this function's only job is threading each
value straight to the launcher's matching `--model`/`--permission-mode`/`--effort` flags (and
running `prompt` through `_build_prompt_with_attachments` first) -- no validation, no defaulting
beyond what the launcher's own argparse/`ClaudeAgentOptions` already does, matching this project's
existing "the client sends a complete, already-valid request" convention for every other call this
generator makes."""
async def:pub start_chat_turn(prompt: str, session_id: str | None, cwd: str | None, attached_paths: list[str], model: str, permission_mode: str, effort: str) -> Generator {
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

        env = dict(os.environ);
        env["PYTHONPATH"] = _build_pythonpath(sys.path);

        full_prompt = _build_prompt_with_attachments(prompt, attached_paths);
        args = [python_bin, _launcher_path(), full_prompt];
        if session_id {
            args.append("--resume");
            args.append(session_id);
        }
        if cwd {
            args.append("--cwd");
            args.append(cwd);
        }
        args.append("--model");
        args.append(model);
        args.append("--permission-mode");
        args.append(permission_mode);
        args.append("--effort");
        args.append(effort);

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
