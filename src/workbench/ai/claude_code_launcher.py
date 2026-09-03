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
"""
import argparse
import asyncio
import json
import sys

from claude_agent_sdk import query, ClaudeAgentOptions
from claude_agent_sdk.types import StreamEvent, AssistantMessage, ResultMessage, TextBlock


def _emit(event: dict) -> None:
    print(json.dumps(event), flush=True)


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
