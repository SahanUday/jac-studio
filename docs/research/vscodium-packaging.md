# Research notes: how VSCodium turns VS Code source into an installable binary

Source: `/home/sahan/dev/vs/vscodium` (VSCodium/vscodium checkout), investigated 2026-08-22.
Grounding reference for the packaging phase in [`../roadmap.md`](../roadmap.md).

VSCodium is not a fork — it's a pinned-commit clone of `microsoft/vscode` plus an overlay
(`patches/*.patch` applied in numbered order, and a `product.json` deep-merged over MS's own via
`jq -s '.[0] * .[1]'`) that strips MS branding/telemetry/marketplace and rebuilds using VS Code's
own build tooling (gulp, `gulp-atom-electron`, Inno Setup, `electron-osx-sign`). It adds nothing
of its own except a Rust/Cargo build for the standalone CLI/tunnel binary.

None of the mechanics of *patching someone else's source* apply to us — jac-studio is written
from scratch. What transfers is the **packaging-a-desktop-app checklist**, independent of runtime:

## Transfers to a Jac-native desktop build

- **One externalized identity/config file**, merged at build time, holding: app name, bundle IDs,
  update-feed URL, extension-registry URL, issue-tracker URL. (VSCodium's `product.json` pattern —
  Jac's `jac.toml [desktop]` block is our equivalent; see `jac-desktop-app.md`.)
- **Per-OS installer formats**: deb/rpm/AppImage (Linux), dmg/zip (macOS), exe/msi/zip (Windows) —
  each OS needs its own packaging step, no shortcut.
- **Code signing is non-negotiable on two of three OSes**: Windows needs Authenticode signing
  (VSCodium uses SignPath, a free-for-OSS signing service, since it holds no cert of its own);
  macOS needs a paid Apple Developer ID cert + `notarytool` submission + `stapler` — Gatekeeper
  will not run an unsigned/unnotarized app. Linux has no signing gate.
- **An auto-update mechanism** with its own hosted feed, decoupled from OS package managers.
- **GitHub-Actions-shaped CI**: separate "validate on PR" vs "publish on cron/dispatch" paths, a
  retry-hardened release-upload step, published checksums.
- **Cross-arch build concerns** (sysroots/cross-compilers) if we ever target arm64 alongside x64.

## Does NOT transfer (pure Electron/vscode-fork artifacts)

- gulp packaging tasks and `gulp-atom-electron` (fetches Electron+ffmpeg binaries) — irrelevant,
  Jac's desktop shell is not Electron (see architecture doc).
- The patch-overlay mechanism itself — only makes sense when rebranding someone else's source.
- Extension-marketplace redirection (VSCodium → open-vsx.org) — only relevant once/if jac-studio
  adopts a vscode-extension-compatible model (an open roadmap question, not decided yet).
- `electron-osx-sign`'s entitlements config and the Inno Setup `.iss` template — Electron-specific
  tooling; the *concept* of "signed installer script" transfers, the tools don't.
- The separate Rust/Cargo CLI-tunnel binary — a vscode-specific remote-tunnel feature.

## Bottom line

Jac's own desktop docs (`jac-desktop-app.md`) already flag installers/code-signing as an **open
gap** (upstream issue #6436) — no cross-compilation, must build on each target OS, no signing
pipeline yet. This VSCodium research confirms that gap is real work regardless of language choice:
even a mature project doing this in Electron needed a dedicated per-OS signing/notarization/
installer pipeline. We should expect to build (or contribute) that pipeline ourselves late in the
roadmap, not assume `jac nacompile` hands us a shippable binary. Tracked as a roadmap item, not a
blocker for anything earlier — MVP phases don't need a signed binary.
