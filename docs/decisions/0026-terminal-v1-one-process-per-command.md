# 0026 — Terminal v1 spawns one process per command, with no persistent shell session

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

Each Enter press spawns a one-shot OS process whose output streams back over SSE. There is no
long-lived shell session behind the terminal panel.

## Why

A stated, deliberate v1 scope cut, taken to get a usable terminal into the earliest build (0007)
rather than to model a pty session correctly.

## Consequences

`cd` and exported environment variables do not persist between commands — a real functional gap a
user will notice, recorded here so it reads as a known cut rather than a bug to be surprised by.
Any future work wanting a real interactive shell (or a REPL) is a genuine redesign of this
mechanism, not an incremental fix.
