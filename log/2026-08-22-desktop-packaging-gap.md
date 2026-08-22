---
id: 2026-08-22-desktop-packaging-gap
date: 2026-08-22
category: missing-feature
severity: major
status: upstream-tracked
phase: 7
subsystem: desktop
jac_version: "unspecified — see jac-desktop-app.md"
related_vscode_ref: ""
upstream_issue: "jaseci/jaseci#6436"
tags: [desktop, packaging, code-signing, installers]
---

`jac nacompile`'s desktop target (native host + OS webview shell, per `jac-desktop-app.md`) has no
code-signing pipeline and no per-OS installer generation yet, and no cross-compilation — you must
build on each target OS. Confirmed against VSCodium's own packaging pipeline
(`research/vscodium-packaging.md`): even a mature Electron-based project needs a dedicated signing/
notarization/installer step per OS, so this isn't a corner Jac cut carelessly — it's real,
unavoidable work regardless of which runtime we'd chosen.

**Impact on jac-studio**: no impact until Phase 7 (desktop packaging is explicitly last in the
roadmap for exactly this reason). Not a blocker for any MVP phase.

**Plan**: build the per-OS signing/installer pipeline ourselves in Phase 7, treating it as
project work rather than waiting on upstream. Revisit this entry if upstream issue #6436 lands
signing/installer support before we get there.
