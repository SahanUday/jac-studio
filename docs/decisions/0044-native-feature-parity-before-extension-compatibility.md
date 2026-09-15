# 0044 — Native feature parity before extension compatibility

- **Date**: 2026-08-31
- **Status**: accepted

## Decision

Per explicit project-sponsor direction, the milestone being driven toward is a complete,
VS-Code-feature-equivalent editor built entirely on trusted, in-process, build-time-loaded Jac
modules — extension-system Phase A is the whole near-term target, not a stepping stone. Phase B
(dynamic loading) and Phase C (sandboxing) become a later, separate, non-blocking track.

## Why

Earlier drafts had filed search, SCM, tasks/problems, language intelligence, the debugger,
notifications and output under "needs the extension system" purely by analogy to how upstream
packages them — none of them actually require dynamic loading or a trust boundary.

## Consequences

Reorders the milestone target, not 0008's technical phasing, which stays correct as written. A
user should get a complete VS-Code-equivalent experience before jac-studio can load a single
third-party extension. Concretely this promoted the LSP and DAP clients into Phase 4 (0045, 0047)
and downgraded the `.vsix` question (0046). "Full marketplace compatibility" is sequenced later,
not abandoned.
