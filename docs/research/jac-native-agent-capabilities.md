# Research notes: Jac's own native AI-agent capabilities

Source: `jac guide jac-by-llm`, `jac mcp --inspect`, and `claude_agent_sdk.ClaudeAgentOptions`'s
real dataclass fields (introspected directly against the installed `0.2.152`) — all against the
same `/home/sahan/dev/jaseci/jac` (dev-mode compiler source) and `.jac/venv` this project already
builds against. Investigated 2026-09-03, prompted by a question about whether jac-native primitives
could do better than mirroring VS Code/TypeScript's approach for some part of jac-studio's AI
provider work. Extends (does not replace) `jac-capabilities.md`'s brief `by llm()` mention with
depth specific to agentic/tool-using capability. Grounding reference for
[`../architecture.md`](../architecture.md); read that document for the actual decisions.

## `by llm(tools=[...])` is a real, working ReAct agent primitive — not just single-shot Q&A

Confirmed via `jac guide jac-by-llm`, not assumed:

```jac
def analyze(question: str) -> str by llm(
    tools=[word_count],          # plain function references, not strings
    temperature=0.2,
    max_react_iterations=5
);
```

`tools=[...]` turns the call into a real ReAct loop (the model can call any listed function,
observe its result, and iterate, up to `max_react_iterations`) — this is the *same category* of
capability an external agentic CLI like Claude Code provides (Read/Edit/Bash/Grep as tools, a
reasoning loop that calls them), just expressed as an ordinary Jac function instead of a spawned
subprocess. Bound methods work as tools too (`by llm(tools=[self.deposit])`), and method-level
`by llm` automatically includes the object's own `has` fields as context.

**Streaming and multi-turn are both native, not something to build**: `stream=True` makes the call
return a generator (`for token in stream_story("space") { ... }`); `conversation=history` (a
caller-owned `list[dict]`) gets each turn appended in place across calls — the same conversational-
continuity need `claude_code_client.jac` currently satisfies via the SDK's `resume`/`session_id`
mechanism, available here as a plain Jac list instead of an opaque session id round-tripped through
a subprocess.

## The concrete implication: a genuinely jac-native agent provider is buildable, no subprocess needed

Nothing about `claude_code_client.jac`'s subprocess-launcher shape (needed specifically because
`claude_agent_sdk` and its dependency closure can't be imported into `.jac` code — see tracker entry
`2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure`) applies to
`by llm()` — it's a first-class Jac language construct, not a Python package import, so it compiles
and runs directly in `.jac` code with none of that restriction.

A native jac-studio agent provider could be `tools=[create_file, run_in_terminal, search_in_files,
get_scm_status, ...]` — literally the **already-built** jac-studio service functions from Phase 4
(`workspace_service.jac`, `terminal_service.jac`, `search_service.jac`), each needing only a `sem`
description for the model to see, no new tool-execution plumbing at all. This would be a fourth
provider alongside Claude Code/Copilot/OpenCode, distinguished by needing no external CLI installed
and no subprocess/PYTHONPATH-bridging complexity — just a model API key (`ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, etc., per `jac guide jac-by-llm`'s provider table) and `jac.toml`'s
`[byllm.model]` config.

**What this does NOT get for free**, and is worth being honest about: an external agentic CLI like
Claude Code brings substantial, already-battle-tested behavior beyond raw tool-calling — permission
prompting, context-window/compaction management, a large curated tool set (Bash, Edit, Grep, Glob,
web search), safety guardrails refined over real usage. A native `by llm(tools=[...])` agent starts
from zero on all of that; it's a real, viable *option*, not an automatic replacement for the
external-tool integrations already built or planned.

## `jac mcp` — a real, working MCP server, already shipped

`jac mcp --inspect` lists a live inventory: 140 resources (the full `jac guide` reference content,
addressable as `jac://docs/...` URIs), 19 tools (`validate_jac`, `check_syntax`, `format_jac`,
`explain_error`, `jac_to_js`, `run_jac`, `search_docs`, ...), 9 prompts (`write_module`,
`write_walker`, `debug_error`, ...). This is Jac's own dev-tooling MCP server — built to help an AI
assistant *write* correct Jac code, not a jac-studio-specific feature — but directly wireable into
the Claude Code integration already built.

**Confirmed, not assumed**: `claude_agent_sdk.ClaudeAgentOptions` has a real `mcp_servers` field
(`dict[str, McpStdioServerConfig | McpSSEServerConfig | McpHttpServerConfig | McpSdkServerConfig]`),
introspected directly from the installed package's dataclass fields. Concretely, `claude_code_client.jac`
could pass `mcp_servers={"jac": {"command": "jac", "args": ["mcp"]}}` (a stdio server config) so
that when a jac-studio user asks Claude Code to fix a `.jac` file, it can call `validate_jac`/
`explain_error`/`jac_to_js` directly instead of shelling out through Bash and hoping `jac check`'s
plain-text output parses correctly — meaningfully richer tool access, and close to free to wire in
given the option already exists.

## What this does NOT cover

- Whether `by llm()`'s ReAct loop is fast/reliable enough for a full agentic coding session at the
  scale Claude Code handles (large multi-file refactors, long tool-call chains) — unresearched, a
  real open question before treating a native agent provider as more than a viable option.
- `ModelPool` (mentioned in `jac guide jac-by-llm` for fallback/load-balancing across raw model
  APIs) is a different concept from swapping full agentic CLI tools — it operates at the "which LLM
  API answers this call" layer (OpenAI vs. Anthropic vs. local), not the "which pre-built agent with
  its own tool set" layer Claude Code/Copilot/OpenCode operate at. Don't conflate the two when
  designing the provider interface.
