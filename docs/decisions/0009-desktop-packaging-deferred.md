# 0009 — Desktop packaging is deliberately last

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Defer `jac nacompile` + OS-native-webview packaging, per-OS installers, code signing and an
auto-update feed to the final phase.

## Why

Unlike Electron, Jac's webview-based desktop shell is a thin layer over the same client bundle
the browser target already uses — there is no separate desktop codebase to maintain in parallel,
so deferring costs nothing.

## Consequences

Accepts that the app is a web app until then: no window controls, no menu bar, and the
`@jac/desktop` capability gate is unreachable (0025). Expect to build the installer/signing
pipeline ourselves — Jac ships none (upstream gap #6436). The in-app update UI is distinct from
the update feed and does not fall out of it for free.
