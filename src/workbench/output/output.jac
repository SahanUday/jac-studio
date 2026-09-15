"""Output panel: renders `output_service.jac`'s channels.
Polls only while `active` (selected tab and panel open), since this mounts once and hides via CSS.
Channel selector is a plain native `<select>`: no `Select` primitive is installed, and a few-item
text dropdown doesn't need Radix's positioning machinery.
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
