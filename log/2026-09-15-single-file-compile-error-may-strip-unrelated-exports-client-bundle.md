---
id: 2026-09-15-single-file-compile-error-may-strip-unrelated-exports-client-bundle
date: 2026-09-15
category: doc-gap
severity: major
status: open
phase: 6
subsystem: tooling
jac_version: "0.37.3 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, client-bundle, compile-error, unconfirmed]
---

## What happened

During Phase 5's post-closure QA round (2026-09-04, see
`docs/milestones/m5-ai-integrations.md`), a genuine compile error in `thinking_indicator.jac`
(`Math.floor()` needing an explicit `as int` cast) reached the browser, immediately followed in
the same terminal log by a cascading `E7001: no export named 'create_file'` for a completely
unrelated file, `workspace_service.jac`.

## Root cause (unconfirmed)

One incident, not a controlled repro. The working hypothesis: a genuine compile error in one file
can leave the client bundler's build in a state where unrelated files silently lose their own
exports too, with no error reported for those other files specifically — only the cascading
"no export named" symptom downstream. This was recorded at the time as a hypothesis, explicitly
distinguished from an earlier, separate theory (memory pressure on a shared machine causing
silent partial client-bundle compiles) that this same investigation had also chased and which this
incident's evidence argues against.

## Fix

None yet — the immediate case was resolved by fixing the real compile error in
`thinking_indicator.jac`, which also made the `workspace_service.jac` symptom disappear.

## Plan

Confirm or refute with a controlled repro: deliberately introduce a compile error in one file,
rebuild the client bundle from a clean cache in an otherwise idle environment, and check whether
an unrelated file's exports vanish from the compiled output with no error reported for that file.
If confirmed, this is a real jac2js build-pipeline robustness gap worth its own upstream report —
a single bad file should fail loudly and only for itself, not silently corrupt sibling files'
output. If the repro doesn't reproduce cleanly, downgrade or close this entry rather than leaving
it open indefinitely on one incident's evidence.
