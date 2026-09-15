# jac-studio

VS Code's capabilities and UX, rebuilt as a [Jac](https://github.com/jaseci-labs/jaseci) web app —
AI-first, not a literal clone.

Monaco is the editor engine and proven libraries cover already-solved problems. Jac carries the
architecture, the services, and the AI layer. The web app is the target; desktop comes later by
bundling the same client.

## Status

Runs locally as a web app with a real workbench: file tree, editor groups and tabs, command
palette, quick open, search, SCM, tasks and problems, an integrated terminal, an outline view,
notifications, and a settings/session layer that persists.

Language intelligence is native — a Jac LSP client speaking to `jac lsp`, giving completion, hover,
go-to-definition, find-references and rename. A DAP client backs debugging. AI assistance runs
through Claude Code with tool approval, multi-file edit diff review, inline chat (`Ctrl+I`), and
AI-backed code actions.

See [`docs/roadmap.md`](docs/roadmap.md) for what's built and what's next.

## Running it

```bash
jac install          # Jac, Python and npm dependencies
jac start --dev      # dev server
jac browse           # open it
```

The integrated terminal is **deny-by-default**: it refuses to run anything until `[terminal]
enabled` is set in `jac.toml`. That's deliberate — granting it is the same trust level as opening
your own shell.

Stop the dev server when you're done; ports 8000 and 8001 should be clear.

## Docs

| Question | Where |
|---|---|
| What's being built, in what order | [`docs/roadmap.md`](docs/roadmap.md) |
| How the system is put together | [`docs/architecture.md`](docs/architecture.md) |
| Why a past call was made | [`docs/decisions/`](docs/decisions/) |
| What a library gives us | [`docs/libraries/`](docs/libraries/) |
| Does VS Code have X, do we cover it | [`docs/vscode-complete-triage.md`](docs/vscode-complete-triage.md) |
| Prior research (dated, point-in-time) | [`docs/research/`](docs/research/) |

Friction hit while building Jac itself is logged to a public challenge tracker —
see [`docs/challenge-tracking.md`](docs/challenge-tracking.md).

## Contributing

`CLAUDE.md` holds the working rules: verify by running, never commit to `main`, and keep the prose
budget. The codebase is deliberately lean on comments — text earns its place or it goes.
