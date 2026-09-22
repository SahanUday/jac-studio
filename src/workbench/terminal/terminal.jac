"""Terminal: xterm.js output pane over a real, reconnectable PTY session (ADR 0078). The session
id persists in sessionStorage so a page refresh reattaches to the same running shell instead of
losing it. Keystrokes pass straight through to the PTY -- no client-side line editing, the real
shell's readline does that now. See docs/libraries/xterm.md, docs/libraries/ptyprocess.md."""

import "@xterm/xterm/css/xterm.css";
import from "react" { useEffect }
import from "@xterm/xterm" { Terminal }
import from "@xterm/addon-fit" { FitAddon }
import from "@xterm/addon-clipboard" { ClipboardAddon }
import from "@xterm/addon-web-links" { WebLinksAddon }
import from "@xterm/addon-search" { SearchAddon }
import from "@xterm/addon-serialize" { SerializeAddon }
import from "@xterm/addon-unicode11" { Unicode11Addon }
import from "@xterm/addon-webgl" { WebglAddon }
import from src.workbench.workspace.workspace_service { get_current_workspace }
import from src.workbench.terminal.terminal_service { open_session, send_input, resize_session }

glob _SESSION_STORAGE_KEY: str = "jac-studio-terminal-session-id";

def:pub app(onFocusChange: any, onNotify: any) -> JsxElement {
    has container_ref: Ref[any] = Ref();
    has term_ref: Ref[any] = Ref();
    has fit_ref: Ref[any] = Ref();
    has search_addon_ref: Ref[any] = Ref();
    has session_id_ref: Ref[str] = Ref("");
    has started_ref: Ref[bool] = Ref(False);
    has search_open: bool = False;
    has search_query: str = "";

    def handle_data(data: str) -> None;
    def handle_terminal_resize(size: any) -> None;
    async def start_session -> None;
    def handle_resize -> None;
    def handle_search_key(e: any) -> None;
    def close_search -> None;
    def open_search -> None;

    can with entry {
        # allowProposedApi: Unicode11Addon's version-switching API is still proposed in xterm.js.
        term = new(Terminal, {"convertEol": False, "fontSize": 13, "cursorBlink": True, "allowProposedApi": True});
        fit = new(FitAddon);
        search_addon = new(SearchAddon);
        term.loadAddon(fit);
        term.loadAddon(new(ClipboardAddon));
        term.loadAddon(new(WebLinksAddon));
        term.loadAddon(search_addon);
        term.loadAddon(new(SerializeAddon));
        term.loadAddon(new(Unicode11Addon));
        term.unicode.activeVersion = "11";
        try {
            term.loadAddon(new(WebglAddon));
        } except Exception {}
        term.open(container_ref.current);
        # Let native browser copy fire when text is selected; otherwise Ctrl/Cmd+C is SIGINT.
        # Ctrl/Cmd+F opens in-terminal search instead of the browser's own page find.
        term.attachCustomKeyEventHandler(lambda (ev: any) {
            is_copy_chord = (ev.ctrlKey or ev.metaKey) and not ev.shiftKey and ev.key == "c";
            if is_copy_chord and term.hasSelection() {
                return False;
            }
            if (ev.ctrlKey or ev.metaKey) and ev.key == "f" {
                open_search();
                return False;
            }
            return True;
        });
        term.onData(handle_data);
        term.onResize(handle_terminal_resize);
        term_ref.current = term;
        fit_ref.current = fit;
        search_addon_ref.current = search_addon;

        session_id = sessionStorage.getItem(_SESSION_STORAGE_KEY);
        if not session_id {
            session_id = crypto.randomUUID();  # jac:ignore[E1032,E1001]
            sessionStorage.setItem(_SESSION_STORAGE_KEY, session_id);  # jac:ignore[E1053]
        }
        session_id_ref.current = session_id;
    }

    useEffect(lambda {
        # rAF-deferred: fitting synchronously inside the callback trips ResizeObserver's loop guard
        observer = new(ResizeObserver, lambda (entries: any) {
            requestAnimationFrame(lambda (t: any) { handle_resize(); });
        });
        observer.observe(container_ref.current);
        return lambda { observer.disconnect(); };
    }, []);

    <div style={{"height": "100%", "width": "100%", "position": "relative"}}>
        <div
            ref={container_ref}
            onFocus={lambda (e: any) { onFocusChange(True); }}
            onBlur={lambda (e: any) { onFocusChange(False); }}
            style={{"height": "100%", "width": "100%", "padding": "0.25rem"}}
        />
        {search_open and (
            <div style={{
                "position": "absolute", "top": "0.25rem", "right": "0.25rem", "zIndex": 10,
                "display": "flex", "gap": "0.25rem", "alignItems": "center",
                "background": "#252526", "border": "1px solid #454545", "borderRadius": "4px",
                "padding": "0.25rem 0.375rem"
            }}>
                <input
                    autoFocus={True}
                    value={search_query}
                    onChange={lambda (e: any) { search_query = e.target.value; }}
                    onKeyDown={handle_search_key}
                    placeholder="Find"
                    style={{
                        "background": "#3c3c3c", "color": "#cccccc", "border": "none",
                        "outline": "none", "fontSize": "12px", "padding": "0.15rem 0.35rem",
                        "width": "10rem"
                    }}
                />
                <button
                    onClick={lambda (e: any) { close_search(); }}
                    style={{"background": "transparent", "border": "none", "color": "#cccccc", "cursor": "pointer"}}
                >
                    X
                </button>
            </div>
        )}
    </div>
}
