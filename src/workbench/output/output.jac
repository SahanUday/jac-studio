"""Output: the panel half of VS Code's Output view (`workbench/contrib/output`), rendering
`output_service.jac`'s channels -- see that module's docstring for why it ships with no real
producer yet (the task runner/LSP/DAP clients later in this same Phase 4 are the intended first
callers) and why a channel is a bounded, non-persisted server-side cache rather than a graph node.

**Polls only while actually the visible tab, not always.** This component is mounted once and
hidden via CSS the same "mount once, hide via CSS" convention `terminal.jac`'s panel already uses
(see `workbench.jac`'s panel-tab-strip docstring) -- so it can't rely on mount/unmount to know when
it's the thing the user is actually looking at. `active` is the signal instead: the poll interval
only runs while this panel is both the selected bottom-panel tab *and* the panel area is open,
clearing itself the moment either stops being true, so a background producer logging away in
`output_service.jac` doesn't cost a fetch every 2s for a panel nobody has open.

**Channel selector is a plain native `<select>`, not a shadcn primitive** -- this project has no
`Select` component installed (`components/ui/` doesn't ship one), and a two-to-few-item dropdown of
plain text channel names doesn't need Radix's positioning/portal machinery to render correctly;
matches the same "hand-build the small chrome pieces no primitive fits" call already made for the
activity bar and the file tree's folder-path input.
"""

import from "react" { useEffect }
import from src.workbench.output.output_service { list_channels, get_channel_content, clear_channel }

def:pub app(active: bool) -> JsxElement {
    has channels: list[str] = [];
    has selected_channel: str = "";
    has content: str = "";

    async def refresh -> None;
    async def handle_clear -> None;
    def handle_select_channel(next_channel: str) -> None;

    useEffect(lambda {
        if not active {
            return lambda {};
        }
        refresh();
        interval_id = setInterval(lambda { refresh(); }, 2000);
        return lambda { clearInterval(interval_id); };
    }, [active, selected_channel]);

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%"}}>
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "padding": "0.25rem 0.5rem", "borderBottom": "1px solid #2A2B2C", "flexShrink": "0"}}>
            <select
                aria-label="Output channel"
                value={selected_channel}
                onChange={lambda (e: any) { handle_select_channel(e.target.value); }}
                disabled={len(channels) == 0}
                style={{
                    "background": "#191A1B",
                    "color": "#CCCCCC",
                    "border": "1px solid #2A2B2C",
                    "borderRadius": "4px",
                    "fontSize": "12px",
                    "padding": "0.15rem 0.4rem"
                }}
            >
                {[<option key="" value="">No output channels</option>] if len(channels) == 0 else [<option key={c} value={c}>{c}</option> for c in channels]}
            </select>
            <button
                aria-label="Clear output"
                title="Clear Output"
                onClick={lambda (e: any) { handle_clear(); }}
                disabled={selected_channel == ""}
                className="codicon codicon-clear-all"
                style={{
                    "background": "transparent",
                    "border": "none",
                    "color": "#8C8C8C" if selected_channel != "" else "#5A5A5A",
                    "cursor": "pointer" if selected_channel != "" else "default",
                    "fontSize": "14px"
                }}
            />
        </div>
        <div style={{"flex": "1", "overflow": "auto", "padding": "0.5rem"}}>
            {(<pre style={{"margin": "0", "fontFamily": "monospace", "fontSize": "12px", "color": "#CCCCCC", "whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{content}</pre>) if content != "" else <div style={{"color": "#5A5A5A", "fontSize": "12px", "fontFamily": "system-ui, sans-serif"}}>No output yet</div>}
        </div>
    </div>
}
