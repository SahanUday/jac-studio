# 0069 — The AI chat subprocess fully isolates from the host's global CLAUDE.md

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

`claude_code_launcher.py` passes `setting_sources=[]` to `ClaudeAgentOptions` — not
`["project", "local"]`, which looked sufficient but wasn't.

## Why

A file literally named `scratch_test.txt` was written to `~/.claude-scratch/` instead of the open
workspace. Root cause, found by reading the real `claude` CLI's own source: `"project"` scope's
CLAUDE.md discovery walks every ancestor directory from `cwd` to the filesystem root with no
special case for `$HOME`, so it rediscovers the operator's own personal global CLAUDE.md (which has
exactly that scratch-file naming rule) through a different code path than the `"user"` scope
exclusion was meant to block. Any real workspace's `cwd` is nested under the OS user's home
directory, so this always applies. Verified against the installed SDK directly with standalone
probe scripts, not just this launcher.

## Consequences

The launcher's process never picks up any CLAUDE.md outside the project it's told to operate in,
including the operator's own personal one — this is a hard requirement for multi-user or
multi-project correctness, not a convenience setting.
