"""Plain Python, not Jac -- mirrors dap_launcher.py's role for debugpy. Runs entirely outside any
.jac-compiled process specifically so `import claude_agent_sdk` (and its heavy transitive closure:
mcp, pydantic, httpx2, truststore, click) never gets pulled into jaclang's own compiler/type-checker,
which chokes on that closure with hundreds of real errors when the import happens at .jac module
scope. See tracker entry
2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure for the full finding
this design is drawn from -- confirmed live, not assumed.

Prints one purpose-built JSON event per line to stdout, flushed immediately, for
claude_code_client.jac's `start_chat_turn` to relay directly as SSE frames -- translating the SDK's
own richer message objects into the small event shape the client actually needs, rather than
forwarding raw SDK messages (which aren't JSON-serializable as-is: AssistantMessage/ResultMessage
are dataclasses, not dicts).

Usage: claude_code_launcher.py <prompt> [--resume <session_id>] [--cwd <path>]

`mcp_servers` points Claude Code at `jac mcp` (a real, working first-party MCP server --
confirmed live via `jac mcp --inspect`, 140 resources/19 tools/9 prompts) over stdio, giving it
structured Jac-specific tools (validate/format/transpile/docs-search) instead of shelling out
through Bash for the same work. `command="jac"` resolves via this process's own inherited PATH
(the same PATH the parent `jac run` server process already resolved `jac` from to start itself),
not an absolute path -- no extra resolution needed since `claude_code_client.jac` already copies
the full parent environment (`dict(os.environ)`) into this launcher's env. Confirmed live: the
`ClaudeAgentOptions.mcp_servers` field and its stdio-server shape
(`{"command": str, "args": list[str]}`) by introspecting the installed `claude_agent_sdk` package
directly, not assumed from docs.

`can_use_tool` closes the tool-approval gap `docs/architecture.md`'s "AI coding tool integrations"
section flags as the single most concrete finding of the whole PR #70 audit: without it, every
Edit/Write/Bash/MCP call ran with whatever the CLI's own non-interactive permission default is,
invisible in jac-studio's UI -- confirmed live before this change (a plain `Write` call was
silently denied outright, a plain MCP tool call the same, neither one ever asking). Confirmed live
that wiring this callback restores the intended behavior: the SDK only invokes it for a tool call
its own permission rules would otherwise interactively prompt for (a benign `Bash` command like
`echo` never reaches it at all; `Write`, and a destructive `Bash` command like `rm`, both do) --
this is Claude Code's own existing risk judgment, not something reimplemented here.

**The approval decision has to cross a real OS-process boundary, the same one `dap_client.jac`'s
own docstring documents for its command channel, for the same underlying reason.** This process
(the launcher) is not even a `.jac`-compiled one -- it is `claude_code_client.jac`'s own spawned
subprocess, further isolated from whatever separate process handles a later, distinct RPC call
like `approve_tool_call`. `can_use_tool` emits a `tool_approval_request` event (relayed to the
browser like any other event this launcher prints) and then polls the same fixed
`_TOOL_APPROVAL_FILE` path `approve_tool_call` writes to, exactly `dap_client.jac`'s
`_DAP_COMMAND_FILE` pattern -- a hardcoded `/tmp` path rather than `tempfile.gettempdir()`, for the
identical reason that module gives (this project's own single-user local dev-tool scope, and the
same live-caught risk of two different processes disagreeing on where a computed temp dir
resolves). No staleness/reset handling is needed here unlike `_DAP_COMMAND_FILE`'s `seq` counter,
`tool_use_id` is already a fresh, SDK-issued unique id per call (confirmed via the SDK's own
`ToolPermissionContext` docstring), so an old decision can never collide with a new one.

**No "always allow this tool" persistence in this first slice, deliberately** -- matching
`claude_code_client.jac`'s own established "no mid-session cancel in this first slice" pattern.
Every tool call gets its own explicit approve/deny; a persisted per-tool trust store (VS Code's
own `IAutoConfirmEntry`) is real, legitimate follow-up work, not silently dropped, once this
core mechanism is in place and used for real.
"""
import argparse
import asyncio
import json
import os
import sys
import time

from claude_agent_sdk import query, ClaudeAgentOptions
from claude_agent_sdk.types import (
    StreamEvent,
    AssistantMessage,
    ResultMessage,
    TextBlock,
    PermissionResultAllow,
    PermissionResultDeny,
)

_TOOL_APPROVAL_FILE = "/tmp/jac_studio_tool_approval_decisions.json"
_TOOL_APPROVAL_TIMEOUT_SECONDS = 300.0
_TOOL_APPROVAL_POLL_SECONDS = 0.3


def _emit(event: dict) -> None:
    print(json.dumps(event), flush=True)


def _read_tool_approval_decisions() -> dict:
    if not os.path.exists(_TOOL_APPROVAL_FILE):
        return {}
    try:
        with open(_TOOL_APPROVAL_FILE, "r") as f:
            return json.load(f).get("decisions", {})
    except Exception:  # noqa: BLE001 -- a torn read (mid-write on the other side) just retries
        return {}


async def _wait_for_tool_approval(tool_use_id: str) -> str | None:
    """Polls `_TOOL_APPROVAL_FILE` for a decision keyed by `tool_use_id`, written by
    `claude_code_client.jac`'s `approve_tool_call` from a separate process (see this module's own
    docstring). Returns `None` on timeout, distinct from an explicit `"deny"`, so the caller can
    report *why* the tool didn't run."""
    deadline = time.monotonic() + _TOOL_APPROVAL_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        decision = _read_tool_approval_decisions().get(tool_use_id)
        if decision is not None:
            return decision
        await asyncio.sleep(_TOOL_APPROVAL_POLL_SECONDS)
    return None


async def _can_use_tool(tool_name, tool_input, context):
    tool_use_id = context.tool_use_id or ""
    _emit({
        "type": "tool_approval_request",
        "tool_use_id": tool_use_id,
        "name": tool_name,
        "input": tool_input,
    })
    decision = await _wait_for_tool_approval(tool_use_id)
    if decision == "allow":
        return PermissionResultAllow()
    if decision == "deny":
        return PermissionResultDeny(message="Denied by the jac-studio user.")
    return PermissionResultDeny(message="Approval timed out; denied automatically.")


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("prompt")
    parser.add_argument("--resume", default=None)
    parser.add_argument("--cwd", default=None)
    args = parser.parse_args()

    options = ClaudeAgentOptions(
        include_partial_messages=True,
        resume=args.resume,
        cwd=args.cwd,
        mcp_servers={"jac": {"command": "jac", "args": ["mcp"]}},
        can_use_tool=_can_use_tool,
    )

    try:
        async for message in query(prompt=args.prompt, options=options):
            if isinstance(message, StreamEvent):
                event = message.event
                if event.get("type") == "content_block_delta":
                    delta = event.get("delta", {})
                    if delta.get("type") == "text_delta":
                        _emit({"type": "text_delta", "text": delta.get("text", "")})
                elif event.get("type") == "content_block_start":
                    block = event.get("content_block", {})
                    if block.get("type") == "tool_use":
                        _emit({"type": "tool_use", "name": block.get("name", "")})
            elif isinstance(message, AssistantMessage):
                # Fallback text for a run with partial-message streaming disabled or a message
                # whose text never arrived as deltas -- ensures the client always has the full
                # text even if it missed/ignored the delta stream.
                text = "".join(b.text for b in message.content if isinstance(b, TextBlock))
                if text:
                    _emit({"type": "text_final", "text": text})
            elif isinstance(message, ResultMessage):
                _emit({
                    "type": "done",
                    "session_id": message.session_id,
                    "cost_usd": message.total_cost_usd,
                    "is_error": message.is_error,
                    "result": message.result,
                })
    except Exception as exc:  # noqa: BLE001 -- relayed to the client as a real error event, not swallowed
        _emit({"type": "error", "message": str(exc)})


if __name__ == "__main__":
    asyncio.run(main())
