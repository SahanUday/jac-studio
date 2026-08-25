"""Terminal: Phase 2's integrated terminal (`docs/roadmap.md`), per `docs/architecture.md`'s
Process Execution section -- xterm.js renders the output pane (Jac has no native terminal-emulator
primitive, so this is npm interop rather than shadcn, same call architecture.md already made), and
every submitted line is sent to `terminal_service.jac`'s `run_in_terminal` over a raw SSE `fetch` --
RPC stubs can't consume a stream (`jac-sv-streaming` guide's "Consuming a stream in the browser"
section), so this bypasses the generated client stub entirely and talks to `/function/run_in_terminal`
directly.

**xterm.js is a raw terminal emulator, not a line editor** -- it hands back individual keystrokes via
`onData`, with no built-in echo or backspace handling. Line editing (`input_buffer`, Backspace,
Enter-to-submit, local echo) is hand-rolled here, the same category of hand-building as the tab row
in `editor_tabs.jac`.

**Mounted once, hidden via CSS, never conditionally rendered** -- same convention
`editor_tabs.jac` uses for `MonacoEditorApp`, and for the same reason: `workbench.jac` toggles the
terminal panel open/closed via a command, and a conditionally-*rendered* (not just hidden) terminal
would remount on every reopen, wiping scrollback each time.

**One command in flight at a time.** Each Enter press spawns an independent server-side process
(see `terminal_service.jac`'s docstring for why this isn't a persistent shell session yet) --
`running` blocks a second submission from overlapping the first's stream rather than letting two
independent process outputs interleave on one screen.

**Focus reporting (2026-08-25, `docs/roadmap.md`'s "when clause" bullet)** -- `onFocusChange`
fires on the wrapping `<div>`'s `onFocus`/`onBlur`, not any xterm.js-specific API: xterm inserts
its own DOM (a canvas plus a hidden textarea that actually receives keystrokes) as children of
that div, and React's `onFocus`/`onBlur` are delegated via `focusin`/`focusout`, which -- unlike
native `focus`/`blur` -- bubble, so a focus/blur transition on any xterm-owned descendant is seen
here regardless of how that descendant was inserted into the DOM. `workbench.jac` uses this to
populate a `terminalFocus` context key its keybinding dispatcher checks -- see its docstring for
why a keybinding like Escape-closes-the-terminal needs to know this and not fire everywhere.

**Re-fitting on resize, and deferring the welcome banner (2026-08-25, caught via real browser
verification, not compiled-bundle inspection -- neither gap showed up in any compiled-JS reading,
only in an actual rendered screenshot)** -- `fit.fit()` at mount time alone sized the terminal to a
near-0x0 box, because `can with entry` runs once, on this component's *first* render, which happens
while its panel is still `display: none` (`terminal_open` defaults to `False` in `workbench.jac`)
-- a hidden element's content box is 0x0 regardless of its CSS `height`/`width`, so `FitAddon` had
nothing real to measure yet and never got asked again once the panel actually became visible. Worse,
the original mount-time `term.write(...)` call for the welcome banner ran against that same
near-0-row buffer, so the banner was silently written into a terminal with nowhere to put it and
never appeared even after a later resize (`fit.fit()` reflows future writes, it doesn't retroactively
recover content already written at the wrong size). Fixed by moving both into a `ResizeObserver` on
the container: it fires with the real size on the panel's first genuine become-visible transition
(a documented `ResizeObserver` behavior -- the callback runs once with current dimensions as soon as
they're non-degenerate, not just on *subsequent* changes), `fit.fit()`s every time, and writes the
banner exactly once, guarded by `banner_written_ref`. This is a genuine acquire/release pair
(`observe`/`disconnect` must share the same observer instance), so it's a manually-imported
`useEffect` alongside `can with entry`, not folded into it.

**`requestAnimationFrame`-deferred callback (2026-08-25, caught live via a real error report in the
server log, not a screenshot this time)** -- `ResizeObserver loop completed with undelivered
notifications` showed up intermittently whenever opening a new file mounted a fresh Monaco instance
elsewhere on the page, since `MonacoEditorApp`'s own `automaticLayout: true` and this component's
`ResizeObserver` both react to the same kind of ancestor layout change, and calling `fit.fit()`
synchronously inside the observer callback risks triggering another layout pass within the same
frame -- exactly the pattern the browser's loop guard exists to catch. Deferring the actual work
into `requestAnimationFrame` is the standard fix: the resize is still handled, just on the next
frame instead of synchronously inside the observer's own callback, which breaks the same-frame
resize-triggers-resize cycle without changing what gets measured or written.
"""

import "@xterm/xterm/css/xterm.css";
import from "react" { useEffect }
import from "@xterm/xterm" { Terminal }
import from "@xterm/addon-fit" { FitAddon }

def:pub app(onFocusChange: any) -> JsxElement {
    has container_ref: Ref[any] = Ref();
    has term_ref: Ref[any] = Ref();
    has fit_ref: Ref[any] = Ref();
    has banner_written_ref: Ref[bool] = Ref(False);
    has input_buffer: str = "";
    has running: bool = False;

    def handle_data(data: str) -> None;
    async def submit_command -> None;
    def handle_resize -> None;

    can with entry {
        term = new(Terminal, {"convertEol": False, "fontSize": 13, "cursorBlink": True});
        fit = new(FitAddon);
        term.loadAddon(fit);
        term.open(container_ref.current);
        term_ref.current = term;
        fit_ref.current = fit;
        term.onData(handle_data);
    }

    useEffect(lambda {
        observer = new(ResizeObserver, lambda (entries: any) {
            requestAnimationFrame(lambda (t: any) { handle_resize(); });
        });
        observer.observe(container_ref.current);
        return lambda { observer.disconnect(); };
    }, []);

    <div
        ref={container_ref}
        onFocus={lambda (e: any) { onFocusChange(True); }}
        onBlur={lambda (e: any) { onFocusChange(False); }}
        style={{"height": "100%", "width": "100%", "padding": "0.25rem"}}
    />
}
