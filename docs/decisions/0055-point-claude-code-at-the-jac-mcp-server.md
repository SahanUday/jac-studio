# 0055 — Point the Claude Code provider at the `jac mcp` server

- **Date**: 2026-09-03
- **Status**: accepted

## Decision

`mcp_servers={"jac": {"command": "jac", "args": ["mcp"]}}` is set on `ClaudeAgentOptions` inside
`claude_code_launcher.py`.

## Why

`jac mcp` is a real, working first-party MCP server — `jac mcp --inspect` lists 140 resources, 19
tools and 9 prompts covering Jac validation/formatting/transpilation/docs-search — and
`mcp_servers` is a real, introspected SDK field. Structured Jac-specific tools
(`validate_jac`, `explain_error`, `jac_to_js`) beat shelling out through Bash for the same work.
Live-verified: a real turn names all 19 `mcp__jac__*` tools and `validate_jac` round-trips over
stdio.

## Consequences

Landed in the launcher, not `claude_code_client.jac` as the original bullet said — that module
never constructs `ClaudeAgentOptions` (0053). Verification also surfaced that the SDK blocks any
MCP tool call without prior approval, exactly as it already did for Bash/Edit/Write — the gap
0056 closes, not a defect of this wiring.
