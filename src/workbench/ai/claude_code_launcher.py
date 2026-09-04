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
       [--model <name>] [--permission-mode <mode>] [--effort <level>]

**`ClaudeAgentOptions.model` still *defaults* to `"haiku"` when `--model` is omitted -- the
standing choice from this launcher's first version is unchanged, only now overridable, not
reversed.** Every feature built against this integration gets exercised for real (`jac browse`, a
genuine running server, genuine API calls -- this project's own "verify empirically" discipline),
which means real API spend on every session, not just this one; defaulting to the cheapest model
keeps that discipline affordable. **A real model picker in `ai_chat.jac` (2026-09-04, real-user
QA) now sends an explicit `--model` on every turn** -- a user asked for the same model-selection
UI real Claude Code/Copilot chat surfaces have, rather than a silently fixed choice with no way to
reach for a stronger model on a harder question. `haiku`/`sonnet`/`opus` are passed through
verbatim as the CLI's own documented short model aliases (confirmed: `"haiku"` already worked as
exactly this kind of alias before this change existed, not a full versioned model id) -- this
launcher does no alias resolution of its own, the same "don't reinvent what the tool already does"
call `mcp_servers` above already makes.

**`--permission-mode`/`--effort` (2026-09-04, real-user QA) thread straight through to
`ClaudeAgentOptions.permission_mode`/`.effort` -- both real fields the installed SDK already
exposes (confirmed by reading `ClaudeAgentOptions`'s own dataclass fields directly, not assumed),
not new behavior invented here.** A user, comparing against a real Claude Code extension
screenshot, asked for its "Manual / Edit automatically / Plan / Auto" mode switcher and its effort
selector. `permission_mode`'s four values used by `ai_chat.jac`'s picker map onto the SDK's own
documented semantics one-to-one: `"default"` (Manual -- every dangerous call still reaches
`can_use_tool` below, this launcher's original, only behavior before this change), `"acceptEdits"`
(Edit automatically), `"plan"` (Plan -- no tool execution at all), `"auto"` (Auto -- the SDK's own
broadest bypass). Modes other than `"default"` mean some or all tool calls never reach
`can_use_tool` at all (the SDK's own permission-mode check short-circuits it, not something this
launcher special-cases) -- so fewer or no approval cards is the *correct*, expected result of
picking one of those modes, not a regression of the approval flow PR #72 built. `effort` is passed
through as one of the SDK's own five documented literal levels unchanged.

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

**`setting_sources=[]` -- full isolation, a real, live-reproduced bug fix, not a defensive
default (2026-09-04, real-user QA, corrected same day after the first fix attempt below turned out
to be insufficient -- also confirmed live, not assumed).** A real user asked this launcher to
"Create a new file called scratch_test.txt", with `--cwd` correctly pointing at their own open
workspace (confirmed live in the server's own request log) -- yet the file landed under
`~/.claude-scratch/<session-id>/`, nowhere near that workspace. Root cause: this launcher runs on
the *same machine, same OS user* as whoever is developing jac-studio itself with their own,
separate Claude Code CLI session -- so a query spawned here was reading that developer's own
personal global `~/.claude/CLAUDE.md`, not anything jac-studio ships or controls. That file's own
real standing rule (verbatim: "Anything throwaway ... goes in `$HOME/.claude-scratch/<session-id>/`,
never inside a project repo") is exactly what fired: the requested file was *literally named*
"scratch_test.txt", and the agent, correctly following instructions it had no way to know weren't
meant for it, obeyed. This isn't specific to that one rule or that one developer's machine -- *any*
end user of jac-studio's shipped AI Chat feature could have their own unrelated global `CLAUDE.md`
silently steering this in-app assistant's behavior on a completely unrelated project, purely
because both run as the same OS user.

**CORRECTION, same day: the first fix, `setting_sources=["project", "local"]` (excluding only
`"user"`), was real progress but did not actually close the bug -- confirmed live, the exact same
`~/.claude-scratch/...` write still happened with that value set.** Diagnosed by reading the real
`claude` CLI's own TypeScript source directly (`utils/claudemd.ts`'s memory-file loader), not
re-guessing from the Python SDK's docstring a second time: `"user"` gates one specific, dedicated
lookup (`getMemoryPath('User')` -- `homedir()/.claude/CLAUDE.md`), but `"project"` gates a
*separate* one that walks every ancestor directory from `cwd` up to the filesystem root looking for
`.claude/CLAUDE.md` in each -- with no special case to stop at, or skip, `$HOME`. Since any real
workspace's `cwd` is necessarily nested *under* the actual OS user's home directory, that ancestor
walk always eventually reaches `$HOME` itself and independently rediscovers
`$HOME/.claude/CLAUDE.md` -- the identical file, reached through the `"project"`-gated code path,
completely bypassing the `"user"` exclusion. Verified both the failure and the fix directly against
the installed SDK (`claude_agent_sdk.query()`, standalone probe scripts, not just this launcher) --
`setting_sources=["project", "local"]` still leaked; `setting_sources=[]` did not, and let a
normal (non-"scratch"-named) file request land correctly in the open workspace with no confusion.
Given `"project"` scope can never be excluded from this ancestor-walk risk while `cwd` is
home-nested (true for every real jac-studio workspace), full isolation is the only setting that is
actually correct here -- not a broader hammer than necessary, the *minimum* one that works. The
trade-off (a workspace's own project-level `CLAUDE.md`, if it ever has one, goes unread too) is
accepted deliberately: predictable, host-independent behavior for jac-studio's own shipped
assistant matters more here than an unbuilt, so-far-unused feature.

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
correlate a later outcome against, no input, no result.

**`system_prompt={"type": "preset", "preset": "claude_code"}` (2026-09-04, real-user QA) -- a real,
live-reproduced bug, found investigating a report that looked at first like a *file-tree* bug and
wasn't.** A user asked the in-app AI Chat to "Create a new file called scratch_test.txt" with a
workspace open; the assistant reported success, but the file never appeared in the Explorer tree.
The natural suspect was `workspace_watcher.jac`, but the terminal log told a different story: the
file had been written to `/tmp/scratch_test.txt`, nowhere near the open workspace `--cwd` pointed
at -- so the watcher (and the tree) were correctly reporting no change *inside the workspace*, since
none had happened there. The real bug was this launcher never setting `system_prompt` at all,
leaving it at the SDK's own default of `None`.

Traced into the installed SDK's own source (`subprocess_cli.py`, not assumed from the dataclass
docstring alone): `system_prompt=None` doesn't mean "use Claude Code's normal default prompt" --
`if self._options.system_prompt is None: cmd.extend(["--system-prompt", ""])`, an *explicit empty
string*, sent to the real CLI as a custom prompt. Confirmed against the real `claude` CLI's own
TypeScript source (the same `/home/sahan/dev/coder/src` checkout used to diagnose the earlier
`setting_sources` leak): `fetchSystemPromptParts` in `utils/queryContext.ts` treats
`customSystemPrompt !== undefined` (true for `""`, same as any other string) as "skip the default
entirely" -- both `getSystemPrompt()` (Claude Code's whole default behavioral prompt) and
`getSystemContext()` are replaced with nothing. Confirmed further, in `constants/prompts.ts`, that
`getSystemPrompt()` is exactly where the `<env>Working directory: ${getCwd()}...</env>` block lives
(`computeEnvInfo`/`computeSimpleEnvInfo`, wired in as the `env_info_simple` section). So this
launcher was running every single turn with the model told nothing at all about where it was
running -- not even its own working directory -- `cwd` only ever set the OS-level subprocess
directory tool calls resolve relative paths against, never anything the model itself could read.
Asked for a file with no explicit path and a name that sounds like a scratch/temp file, and given
zero anchoring context saying otherwise, the model reasonably fell back to its own pretrained
instinct (a `/tmp`-shaped path) rather than the actual open workspace.

**Fix is the preset, not a hand-written prompt** -- `{"type": "preset", "preset": "claude_code"}`
restores the real default prompt (env info, working-directory framing, every built-in behavioral
instruction Claude Code normally ships with) without writing a parallel, driftable copy of it here.
This does **not** reopen the `setting_sources=[]` leak fixed earlier the same day: confirmed via the
same source reading that CLAUDE.md loading is a completely separate CLI flag
(`--setting-sources`, `subprocess_cli.py`) from `--system-prompt`, independent knobs, and
`setting_sources=[]` above is untouched by this change."""
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
    parser.add_argument("--model", default=None)
    parser.add_argument("--permission-mode", default=None)
    parser.add_argument("--effort", default=None)
    args = parser.parse_args()

    options = ClaudeAgentOptions(
        include_partial_messages=True,
        resume=args.resume,
        cwd=args.cwd,
        mcp_servers={"jac": {"command": "jac", "args": ["mcp"]}},
        can_use_tool=_can_use_tool,
        model=args.model or "haiku",
        permission_mode=args.permission_mode,
        effort=args.effort,
        setting_sources=[],
        system_prompt={"type": "preset", "preset": "claude_code"},
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
