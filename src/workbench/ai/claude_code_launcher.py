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

**`ClaudeAgentOptions.model` is pinned to `"haiku"`, a deliberate standing choice, not a
leftover from one PR's live-verification pass.** Every feature built against this integration
gets exercised for real (`jac browse`, a genuine running server, genuine API calls -- this
project's own "verify empirically" discipline), which means real API spend on every session, not
just this one. Pinning to the cheapest model keeps that discipline affordable across the whole
run of AI-integration work, not only while implementing it -- correctness of the plumbing this
launcher owns (event shapes, streaming, tool approval, MCP wiring) doesn't depend on which model
answers, so there's no accuracy tradeoff being made here worth trading back for.

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

**`Edit`/`Write` approval requests carry a real before/after diff, not just the raw tool input.**
Closes the multi-file-edit-review gap `docs/architecture.md` flags right alongside tool approval --
before this, a file edit had no preview at all; the generic JSON dump (still what every other tool
gets) doesn't tell a user what a `Write` call is about to overwrite, or what an `Edit` call's
`old_string`/`new_string` actually changes in context. Both tool input shapes confirmed live, not
assumed (`{"file_path", "content"}` for `Write`; `{"file_path", "old_string", "new_string",
"replace_all"}` for `Edit`) -- `_diff_preview_for_tool_call` reads the file's current on-disk
content (empty string for a not-yet-existing file, `Write`'s own new-file case) as `original_text`,
and derives `modified_text` the same way the real tool would apply it (`Write`: the given content
outright; `Edit`: one `str.replace` call, `count=-1` only when `replace_all` is set, otherwise
exactly one occurrence -- matching the real tool's own documented single-replacement default so the
preview doesn't over- or under-represent what will actually change). Every other tool name (`Bash`,
the `jac mcp` tools, ...) gets neither field, and the client falls back to its existing generic
card -- no attempt made here to guess at a shape for a tool this project hasn't verified live (a
possible `MultiEdit` tool included; a probe for it timed out inconclusively rather than confirming
a real shape, so it deliberately isn't special-cased).

**A tool call's full lifecycle is now three separate events, not one bare name, closing item 6 of
`docs/architecture.md`'s "Reframed 2026-09-03" AI section (richer agent-session visualization).**
`tool_use_start` (immediate, at `content_block_start` -- `id`+`name` only, `input` isn't populated
yet at this point in the stream) lets a client show a step the instant it begins; `tool_use_input`
(from the completed `AssistantMessage`'s own `ToolUseBlock`, confirmed live that this is the first
point the full `input` dict actually exists) fills in the arguments; `tool_result` (from the
`UserMessage`/`ToolResultBlock` the SDK yields once the tool actually finishes -- confirmed live
this fires identically for a real execution *and* for a `can_use_tool` denial, whose own message
string arrives here as `is_error=True` content, not as a separate mechanism) carries the outcome.
All three share the same `tool_use_id` as the join key, exactly like the pre-existing
`tool_approval_request`/`approve_tool_call` pairing. Replaces the old single `{"type": "tool_use",
"name": ...}` event, which gave a client no way to show anything beyond "a tool started" -- no id to
correlate a later outcome against, no input, no result."""
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
    UserMessage,
    ResultMessage,
    TextBlock,
    ToolUseBlock,
    ToolResultBlock,
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


def _read_file_safe(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception:  # noqa: BLE001 -- missing/unreadable/binary all collapse to "no prior content"
        return ""


def _stringify_tool_result_content(content) -> str:
    """`ToolResultBlock.content` is `str | list[dict] | None` depending on the tool (confirmed live:
    a plain str for Bash/Write, a denied call's synthetic message is also a plain str) -- collapses
    every shape to display text rather than guessing one is the only real one."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts = []
    for item in content:
        if isinstance(item, dict) and "text" in item:
            parts.append(str(item["text"]))
        else:
            parts.append(json.dumps(item))
    return "\n".join(parts)


def _diff_preview_for_tool_call(tool_name: str, tool_input: dict) -> tuple[str, str] | None:
    file_path = tool_input.get("file_path")
    if not file_path:
        return None
    if tool_name == "Write":
        return (_read_file_safe(file_path), tool_input.get("content", ""))
    if tool_name == "Edit":
        original = _read_file_safe(file_path)
        old_string = tool_input.get("old_string", "")
        new_string = tool_input.get("new_string", "")
        count = -1 if tool_input.get("replace_all", False) else 1
        return (original, original.replace(old_string, new_string, count))
    return None


async def _can_use_tool(tool_name, tool_input, context):
    tool_use_id = context.tool_use_id or ""
    event = {
        "type": "tool_approval_request",
        "tool_use_id": tool_use_id,
        "name": tool_name,
        "input": tool_input,
    }
    diff = _diff_preview_for_tool_call(tool_name, tool_input)
    if diff is not None:
        event["original_text"] = diff[0]
        event["modified_text"] = diff[1]
    _emit(event)
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
        model="haiku",
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
                        _emit({
                            "type": "tool_use_start",
                            "tool_use_id": block.get("id", ""),
                            "name": block.get("name", ""),
                        })
            elif isinstance(message, AssistantMessage):
                # Fallback text for a run with partial-message streaming disabled or a message
                # whose text never arrived as deltas -- ensures the client always has the full
                # text even if it missed/ignored the delta stream.
                text = "".join(b.text for b in message.content if isinstance(b, TextBlock))
                if text:
                    _emit({"type": "text_final", "text": text})
                # The full tool_use input only exists once the block finishes streaming (the
                # content_block_start above fires with an empty input) -- confirmed live via a
                # direct query() probe (AssistantMessage.content carries a fully-populated
                # ToolUseBlock). Fills in what tool_use_start's own immediate feedback couldn't.
                for b in message.content:
                    if isinstance(b, ToolUseBlock):
                        _emit({
                            "type": "tool_use_input",
                            "tool_use_id": b.id,
                            "name": b.name,
                            "input": b.input,
                        })
            elif isinstance(message, UserMessage):
                # A tool's result (success, failure, or a denied call's synthetic error) comes back
                # as a UserMessage carrying ToolResultBlock(s) -- confirmed live via query(), both
                # for a real Bash/Write execution and for a can_use_tool denial (the deny message
                # itself arrives here as is_error=True content, not as a separate event).
                content = message.content
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, ToolResultBlock):
                            _emit({
                                "type": "tool_result",
                                "tool_use_id": b.tool_use_id,
                                "is_error": bool(b.is_error),
                                "content": _stringify_tool_result_content(b.content),
                            })
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
