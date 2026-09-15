# 0053 — `claude_code_launcher.py` stays plain Python, driven as a subprocess

- **Date**: 2026-09-03
- **Status**: accepted

## Decision

`claude_agent_sdk` is never imported into `.jac`-compiled code. The SDK lives in a plain-Python
launcher spawned as a subprocess; `claude_code_client.jac` only talks to that process.

## Why

`import claude_agent_sdk` pulls in a dependency closure (mcp, pydantic, httpx2, truststore, click)
that explodes jaclang's own compiler/type-checker with hundreds of errors — confirmed live before
the design was settled, not assumed. Tracker entry
`2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure`. Mirrors
`dap_launcher.py`'s identical role for debugpy.

## Consequences

Load-bearing, not stylistic: anything touching `ClaudeAgentOptions` must live in the launcher.
MCP wiring (0055) and the diff preview computation (0057) landed there for exactly this reason,
not where the original roadmap bullets said. Cross-process state needs an explicit channel
(0049). The same check applies before importing any large Python package into `.jac` code.
