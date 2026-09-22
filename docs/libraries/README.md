# Library notes

jac-studio reuses proven libraries for solved problems. Each note here records what a library
actually gives us, so later work doesn't re-research it or miss a capability we already pay for.

**Write a note when a library is wired into an implementation — not before.** A note for a package
we haven't used yet is speculation, not a record.

The most valuable section in each note is *"available but not yet used"*: that's what turns a
dependency into a map of what can be built next cheaply.

| Library | Used for | Note |
|---|---|---|
| monaco-editor | Editor engine | [monaco.md](monaco.md) |
| xterm.js | Terminal rendering | [xterm.md](xterm.md) |
| ptyprocess | Real PTY session backing the terminal | [ptyprocess.md](ptyprocess.md) |

`jac.toml` is the authoritative list of dependencies and versions. Check it before assuming what's
available.
