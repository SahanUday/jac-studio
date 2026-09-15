# xterm.js — `@xterm/xterm` ^5.5.0, `@xterm/addon-fit` ^0.10.0

What we use it for: rendering the integrated terminal's output pane. Jac has no native
terminal-emulator primitive, so this is one of the few UI pieces reached via npm rather than shadcn.
Where it's wired in: `src/workbench/terminal/terminal.jac` + `terminal.impl.jac`.

## Capabilities we use

| Capability | API | Notes |
|---|---|---|
| Terminal instance | `new Terminal({convertEol, fontSize, cursorBlink})` | `convertEol: False`, so we emit `\r\n` ourselves |
| Writing output | `term.write(...)` | streamed command output, prompt, banner |
| Keystroke input | `term.onData(handler)` | raw keystrokes, see the gotcha below |
| Container fitting | `FitAddon` → `term.loadAddon(fit)`, `fit.fit()` | re-fit on every resize |
| Styling | `import "@xterm/xterm/css/xterm.css"` | required, or the terminal renders unstyled |

## Available but not yet used

None of these are installed — each is a separate `@xterm/addon-*` package.

| Capability | Addon | Possible use |
|---|---|---|
| Clickable URLs | `addon-web-links` | make paths and URLs in output actionable |
| In-terminal find | `addon-search` | VS Code has Ctrl+F inside the terminal |
| GPU-accelerated rendering | `addon-webgl` | throughput on large output |
| Buffer serialization | `addon-serialize` | persist or restore terminal contents across reloads |
| Full Unicode width | `addon-unicode11` | correct rendering of wide glyphs |
| Resize notifications | `term.onResize` | tell the backend the real column/row count |

## Limits and gotchas

- **xterm.js is a raw emulator, not a line editor.** `onData` hands back individual keystrokes with
  no echo, no backspace handling, no line buffering. Everything a shell prompt does — the input
  buffer, Backspace, Ctrl+C, the prompt itself — is ours to implement, and is.
- **`fit.fit()` at mount time alone is not enough.** The container can still be degenerate at that
  point, which sizes the terminal wrong, and `fit.fit()` reflows *future* writes only — it does not
  retroactively reflow what's already on screen. Wait for non-degenerate dimensions before writing
  the banner, and re-fit on every resize.
- **Focus tracking uses the wrapping `<div>`'s `onFocus`/`onBlur`**, not any xterm API. xterm
  inserts its own descendants; native focus/blur bubble, so a transition on any xterm-owned
  descendant is visible on the wrapper.
- **There is no PTY.** Commands go to the backend over ordinary RPC and stream back via SSE — this
  is not a real shell session, so interactive programs, job control and TTY-aware behavior don't
  work. A genuine PTY would be a separate piece of work.
- **The terminal is deny-by-default.** `[terminal] enabled = false` in `jac.toml` blocks execution
  until explicitly granted.

## Integration conventions in this codebase

- **Fit inside a `ResizeObserver`, not `can with entry`.** The panel first renders while
  `display: none`, so the content box is 0×0 at mount. It's a genuine observe/disconnect
  acquire-release pair, which is why it uses a manual effect.
- **Defer the fit with `requestAnimationFrame`.** Fitting synchronously inside the observer trips
  `ResizeObserver loop completed with undelivered notifications`, because Monaco's
  `automaticLayout: true` and this observer react to the same ancestor layout change.
- **One command in flight at a time.** Each Enter spawns an independent server process; without the
  guard, two output streams interleave on one screen.
