# xterm.js — `@xterm/xterm` ^5.5.0 + addons

What we use it for: rendering the integrated terminal's output pane, now over a real PTY session
(ADR 0078). Jac has no native terminal-emulator primitive, so this is one of the few UI pieces
reached via npm rather than shadcn.
Where it's wired in: `src/workbench/terminal/terminal.jac` + `terminal.impl.jac`.

## Capabilities we use

| Capability | API | Notes |
|---|---|---|
| Terminal instance | `new Terminal({convertEol, fontSize, cursorBlink, allowProposedApi})` | `convertEol: False` -- the real PTY sends its own `\r\n`. `allowProposedApi: True` is required by `Unicode11Addon`'s `activeVersion` setter |
| Writing output | `term.write(...)` | raw PTY bytes, decoded UTF-8, written as-is -- no client-side transform |
| Keystroke input | `term.onData(handler)` | raw keystrokes passed straight through to the PTY; no client-side line editing |
| Container fitting | `FitAddon` -> `term.loadAddon(fit)`, `fit.fit()` | re-fit on every resize |
| Resize notification | `term.onResize(handler)` | drives `resize_session` so the PTY's `TIOCSWINSZ` matches the real pane size |
| Copy/paste | `@xterm/addon-clipboard`'s `ClipboardAddon` (default `Base64`/`BrowserClipboardProvider`) | OSC 52 -- lets programs *inside* the shell (tmux, vim) read/write the system clipboard. Native browser copy-on-select/paste is xterm's own built-in behavior, not this addon -- see `attachCustomKeyEventHandler` below |
| Clickable links | `@xterm/addon-web-links`'s `WebLinksAddon` | paths/URLs in output become clickable |
| In-terminal find | `@xterm/addon-search`'s `SearchAddon` | `findNext`/`findPrevious`, driven by a small find bar opened on Ctrl/Cmd+F |
| Buffer serialization | `@xterm/addon-serialize`'s `SerializeAddon` | loaded for future use; scrollback replay on reconnect is currently served server-side (the daemon's `output.log`), not this addon |
| Full Unicode width | `@xterm/addon-unicode11`'s `Unicode11Addon` + `term.unicode.activeVersion = "11"` | correct rendering for TUI programs, now that they actually run |
| GPU-accelerated rendering | `@xterm/addon-webgl`'s `WebglAddon` | loaded best-effort inside a `try/except` -- falls back to the default renderer if WebGL is unavailable |
| Custom key handling | `term.attachCustomKeyEventHandler(fn)` | returns `False` to let the browser handle Ctrl/Cmd+C natively when there's a selection (else it's SIGINT), and to intercept Ctrl/Cmd+F for the find bar instead of the browser's own page find |
| Styling | `import "@xterm/xterm/css/xterm.css"` | required, or the terminal renders unstyled |

## Limits and gotchas

- **xterm.js is a raw emulator, not a line editor.** `onData` hands back individual keystrokes with
  no echo, no backspace handling. That's now the real shell's job (its own readline), not ours --
  the PTY (`ptyprocess`, see [notes](ptyprocess.md)) is what changed this from a real gap into a
  non-issue.
- **`fit.fit()` at mount time alone is not enough.** The container can still be degenerate at that
  point, which sizes the terminal wrong, and `fit.fit()` reflows *future* writes only. Wait for
  non-degenerate dimensions before starting the session, and re-fit on every resize.
- **Focus tracking uses the wrapping `<div>`'s `onFocus`/`onBlur`**, not any xterm API. xterm
  inserts its own descendants; native focus/blur bubble, so a transition on any xterm-owned
  descendant is visible on the wrapper.
- **The terminal is deny-by-default.** `[terminal] enabled = false` in `jac.toml` blocks session
  creation and all session I/O (`open_session`, `attach_session`, `send_input`, `resize_session`)
  until explicitly granted. `close_session` is deliberately the one exception -- see its docstring.
- **`ClipboardAddon`'s default constructor** (`new(ClipboardAddon)`, no args) already resolves to
  `Base64`/`BrowserClipboardProvider` -- confirmed by reading the addon's own source, not assumed
  from the type declarations, which don't state the default.
- **Untrusted, JS-`dispatchEvent`-synthesized `KeyboardEvent`s do not reach xterm's input
  pipeline at all** -- confirmed live (not even a plain character reaches `onData`). Genuine
  CDP-level trusted input (`jac browse type`/`press`) works for ordinary keys and Enter, but
  `jac browse press` did not reliably reproduce modifier chords (Ctrl+C, Ctrl+F) in this session --
  a browser-automation tooling limitation, not an xterm or our-code issue. Verify modifier-chord
  behavior by hand in a real browser, not headless automation.

## Integration conventions in this codebase

- **Fit inside a `ResizeObserver`, not `can with entry`.** The panel first renders while
  `display: none`, so the content box is 0x0 at mount. It's a genuine observe/disconnect
  acquire-release pair, which is why it uses a manual effect.
- **Defer the fit with `requestAnimationFrame`.** Fitting synchronously inside the observer trips
  `ResizeObserver loop completed with undelivered notifications`, because Monaco's
  `automaticLayout: true` and this observer react to the same ancestor layout change.
- **The session starts on the first real fit**, not at mount -- mirrors the old banner-write timing,
  now starting `open_session`/`attach_session` once real dimensions are known instead.
