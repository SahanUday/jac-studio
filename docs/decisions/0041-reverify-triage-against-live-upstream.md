# 0041 — Periodically re-verify the triage docs against live upstream source

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Before each new milestone, do more than reread `vscode-complete-triage.md`: periodically re-verify
it against the live `microsoft/vscode` source (`gh api`), not just against its own prior text.

## Why

A live-source check found real gaps twice in one milestone: the entire `workbench/browser/parts/*`
tree had never been triaged (0040), and the current default theme pair was not what our own docs
said it was (0033). Rereading our own documents could not have found either.

## Consequences

Accepts that our triage of "every one of upstream's 158 feature areas" is a snapshot of a moving
target, not a settled inventory. A claim of completeness in our own docs is not evidence about
upstream today.
