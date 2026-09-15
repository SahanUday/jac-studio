# 0018 — Editor core continues native

- **Date**: 2026-08-23
- **Status**: reversed — see [0020](0020-editor-engine-is-real-monaco.md)

## Decision

After Phase 1's prototype, keep building the editor on the from-scratch ported engine (piece
tree, interval tree, prefix-sum computer) plus a hand-built native rendering component, rather
than standing up a Monaco-embed bridge.

## Why

Made with a working prototype in hand, as the roadmap required, not in the abstract: it met Phase
1's exit criteria, round-tripped real keyboard input through the real ported buffer, and its two
found gaps (request ordering, rendering virtualization) were ordinary bounded engineering. Monaco
would have replaced the ported buffer's role rather than composed with it. Recorded as
`2026-08-23-editor-core-native-vs-monaco-decided-native`.

## Consequences

Reversed two days later (0020) as a reuse-over-reinvention call — **not** a verdict that native
failed, and this record exists so nobody re-reads the reversal as "the native attempt didn't
work." The archived engine at `internal/native-editor-archive/` is a real, working answer to "can
Jac build a text-editing widget."
