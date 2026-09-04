---
id: 2026-09-04-empty-system-prompt-strips-default-env-info-and-behavior
date: 2026-09-04
category: resolved
severity: major
status: resolved
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [ai-chat, claude-agent-sdk, claude-code-integration, system-prompt, real-user-qa]
---

## What happened

Real-user QA (not a synthetic test): asked the in-app AI Chat, with a workspace open, to "Create a
new file called scratch_test.txt". The assistant reported success, and the file genuinely existed
on disk -- but at `/tmp/scratch_test.txt`, nowhere near the open workspace `--cwd` pointed at. It
looked at first like a file-tree bug (the new file never appeared in the Explorer), and the
watcher was the natural first suspect since it had just been rewritten that same day (see
`2026-09-04-...` -- multiple entries this same day). It wasn't: the terminal log showed the write
target directly, and a real OS-level watch (once built) correctly reported nothing changed inside
the workspace, because nothing had. The Explorer and the watcher were both behaving correctly.

## Root cause

`claude_code_launcher.py` (`src/workbench/ai/claude_code_launcher.py`) constructs
`ClaudeAgentOptions` for every AI Chat turn and never set `system_prompt`, leaving it at the
`claude_agent_sdk` package's own dataclass default of `None`.

Traced into the *installed* SDK's own source, not assumed from its docstring:
`_internal/transport/subprocess_cli.py` --

```python
if self._options.system_prompt is None:
    cmd.extend(["--system-prompt", ""])
```

`None` does not mean "use Claude Code's normal default prompt." It sends the real `claude` CLI an
*explicit empty custom prompt* (`--system-prompt ""`).

Cross-checked against a real `claude` CLI TypeScript source checkout (the same one used to
diagnose an earlier `setting_sources` CLAUDE.md leak this same day):
`utils/queryContext.ts`'s `fetchSystemPromptParts` treats `customSystemPrompt !== undefined` (true
for `""`, same as any other string, including empty) as "skip the default build entirely" --
`getSystemPrompt()` (the whole default Claude Code behavioral prompt) and `getSystemContext()`
(git status, cache-breaker) are both replaced with nothing. `constants/prompts.ts` confirmed
`getSystemPrompt()` is exactly where the `<env>Working directory: ${getCwd()}...</env>` block
lives (`computeEnvInfo`/`computeSimpleEnvInfo`, wired in as the `env_info_simple` section).

So this launcher was running every single turn with the model told nothing at all about where it
was running -- not even its own working directory. `cwd` on `ClaudeAgentOptions` only sets the
OS-level subprocess directory tool calls resolve relative paths against; it is never surfaced to
the model itself unless the default system prompt (or something bespoke) says so in text. Asked
for a file with no explicit path and a name that sounds like a scratch/temp file, with zero
anchoring context saying otherwise, the model fell back to its own pretrained instinct (a
`/tmp`-shaped path) rather than the actual open workspace.

## Fix

```python
system_prompt={"type": "preset", "preset": "claude_code"},
```

Restores the real default prompt (env info, working-directory framing, every built-in behavioral
instruction Claude Code normally ships with) without hand-writing a parallel, driftable copy of it
in this project.

Confirmed this does **not** reopen the earlier `setting_sources=[]` CLAUDE.md leak fix (also
2026-09-04): `--setting-sources` and `--system-prompt` are independent CLI flags
(`subprocess_cli.py`), and CLAUDE.md loading is gated entirely by the former.

## Plan

No jaseci/SDK change needed -- `system_prompt=None` sending an explicit empty prompt is
documented, intentional SDK behavior (verified directly in the installed package's own source),
not a bug in `claude_agent_sdk` itself. The actual, permanent-correct practice for any future
`ClaudeAgentOptions` construction in this codebase (or any project embedding this SDK) is: never
leave `system_prompt` at its default unless you deliberately want a fully bare, context-free model
with no working-directory awareness -- always pass either the `{"type": "preset", "preset":
"claude_code"}` preset, or a fully custom prompt that itself states the cwd/environment. Worth a
one-line callout in this project's own `docs/architecture.md` "AI coding tool integrations"
section so a future contributor adding a second `ClaudeAgentOptions` call site (a different
launcher, a batch/headless mode) doesn't rediscover this the same way.
