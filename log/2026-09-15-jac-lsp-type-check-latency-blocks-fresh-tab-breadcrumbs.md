---
id: 2026-09-15-jac-lsp-type-check-latency-blocks-fresh-tab-breadcrumbs
date: 2026-09-15
category: ergonomics
severity: minor
status: workaround
phase: 6
subsystem: editor-core
jac_version: "0.37.3 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [lsp, jac-lsp, breadcrumbs, document-symbol, performance]
---

## What happened

Found auditing `monaco_editor.jac` during a codebase-wide comment/docstring cleanup (not a new
regression): a freshly opened `.jac` tab's breadcrumb bar stays empty for several seconds, even for
a small file.

## Root cause

`jac lsp` was measured taking 30+ seconds to type-check a 7-line file before answering
`textDocument/documentSymbol`. The handler answers from the server's current analysis state rather
than blocking until a fresh parse completes, so a request made right after `textDocument/didOpen`
can return stale/empty symbols for a file the server hasn't finished processing yet. There is no
push notification from the server when its symbol data for a file changes, so the client has no
event to react to.

## Fix

`monaco_editor.jac` does one bounded retry of the `documentSymbol` request after a 4-second delay.
This is an explicit partial mitigation, not a fix: files that take longer than 4s to type-check
still show an empty breadcrumb bar indefinitely, and the retry adds a fixed delay even when the
server would have answered sooner.

## Plan

The real fix needs one of: (a) `jac lsp` exposing a "symbols changed" push (e.g. an
unsolicited `textDocument/documentSymbol`-shaped notification, or piggybacking on
`textDocument/publishDiagnostics` since that already fires post-parse), or (b) a documented,
reliable way for a client to know when the server's analysis for a given document version is
current, so a client-side poll can be driven by that instead of a fixed timer. Either belongs
upstream in jaclang's LSP server, not in jac-studio's client. Until then, the workaround stays as
is; consider raising the retry to cover more files if 4 seconds proves too short in practice.
