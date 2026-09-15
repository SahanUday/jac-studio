"""Streams a Claude Code turn by spawning `claude_code_launcher.py` (plain Python) and relaying its
JSON event lines as SSE frames. Never `import claude_agent_sdk` from `.jac` -- it explodes the
compiler (tracker 2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure).
`cwd` must be resolved by the caller, never inside the generator
(tracker 2026-09-05-sse-generator-root-scoped-graph-query-unreliable). Gated on `[terminal] enabled`."""

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

"""Lexicographically first, so the choice among several candidates is deterministic."""
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

def:pub _build_pythonpath(path_entries: list[str]) -> str {
    entries = [p for p in path_entries if p];
    return os.pathsep.join(entries);
}

def _launcher_path -> str {
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude_code_launcher.py");
}

glob _ATTACHMENT_MAX_CHARS: int = 50000;

"""Reads each attached file and prepends its content to the prompt. See ADR 0076."""
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

"""The one SSE-streamed entry point; `session_id` continues an existing conversation via `resume`.
`attached_paths`/`model`/`permission_mode`/`effort` are the client's current picker state, sent
fresh each turn and threaded straight to the launcher's matching flags -- no validation here beyond
what the launcher's own `ClaudeAgentOptions` already does."""
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

        # The embedded runtime cache has none of this project's `[dependencies]` (those live in
        # `.jac/venv`), so the launcher cannot import `claude_agent_sdk` without this.
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
                # A non-JSON line is a launcher crash (traceback, import error), not an event.
                yield json.dumps({"type": "error", "message": text});
            }
        }
        await proc.`wait();
    }
    report stream();
}

glob _TOOL_APPROVAL_FILE: str = "/tmp/jac_studio_tool_approval_decisions.json";

"""Handed to the launcher process through `_TOOL_APPROVAL_FILE`; only the literal `"allow"` is
approval, anything else reads back as a deny."""
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
