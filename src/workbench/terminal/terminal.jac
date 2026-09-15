"""Terminal: xterm.js output pane. Line editing (echo, Backspace, Ctrl+C, the prompt) is
hand-rolled in the impl -- xterm is a raw emulator. Submitted lines go to `run_in_terminal` over a
raw SSE `fetch`, since RPC stubs cannot consume a stream. Fitting and the welcome banner are
deferred into a `ResizeObserver` because the panel mounts hidden. See `docs/libraries/xterm.md`."""

import "@xterm/xterm/css/xterm.css";
import from "react" { useEffect }
import from "@xterm/xterm" { Terminal }
import from "@xterm/addon-fit" { FitAddon }

def:pub app(onFocusChange: any, onNotify: any) -> JsxElement {
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
        # rAF-deferred: fitting synchronously inside the callback trips ResizeObserver's loop guard
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
