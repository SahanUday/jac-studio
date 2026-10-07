"""The Keyboard Shortcuts tab: every command with its key, when-clause and source, a search box that
also matches keys, and a recorder (click a row's pencil, press the chord, Enter to accept, Esc to
cancel). Writes go to `keybindings.json` through the registry and are reported via `onChanged` so the
workbench re-reads the commands. The recorder input carries `data-recording-keybinding` so the global
key handler leaves it alone. Handlers live in `keybindings_editor.impl.jac`."""

import from "react" { useEffect }
import from src.workbench.commands.command_registry {
    list_commands, set_command_keybinding, clear_command_keybinding, reset_command_keybinding
}
import from src.workbench.commands.keybinding_label { format_keybinding }
import from src.workbench.commands.keybinding_chord { chord_from_event }
import from src.workbench.commands.keybindings_view { visible_commands, conflicts_for }

glob FIELD_STYLE: dict[str, str] = {
    "background": "#3c3c3c", "border": "1px solid #3c3c3c", "borderRadius": "3px", "color": "#cccccc",
    "padding": "0.3rem 0.5rem", "fontSize": "13px", "colorScheme": "dark"
};

glob LINK_STYLE: dict[str, str] = {
    "background": "none", "border": "none", "color": "#3794ff", "cursor": "pointer", "fontSize": "12px", "padding": "0"
};

glob ICON_BUTTON_STYLE: dict[str, str] = {
    "background": "none", "border": "none", "color": "#cccccc", "cursor": "pointer", "padding": "0.15rem 0.3rem", "opacity": "0.8"
};

glob CHIP_STYLE: dict[str, str] = {
    "background": "#3c3c3c", "borderRadius": "3px", "padding": "0.1rem 0.4rem", "fontSize": "12px", "marginRight": "0.3rem"
};

glob GRID: str = "minmax(200px, 3fr) minmax(140px, 2fr) minmax(90px, 1fr) 70px 90px";

def:pub app(active: bool, onChanged: any, onOpenJson: any) -> JsxElement {
    has commands: list[dict[str, any]] = [];
    has query: str = "";
    has editing: str = "";
    has recorded: str = "";
    has error: str = "";

    async def refresh -> None;
    async def commit -> None;
    async def clear(command_id: str) -> None;
    async def reset(command_id: str) -> None;
    def start_recording(command_id: str) -> None;
    def cancel_recording -> None;
    def record_key(e: any) -> None;

    useEffect(lambda {
        if active {
            refresh();
        }
    }, [active]);

    shown = visible_commands(commands, query);
    clashes = conflicts_for(commands, recorded, editing) if recorded != "" else [];

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%", "fontFamily": "system-ui, sans-serif", "color": "#cccccc", "colorScheme": "dark"}}>
        <div style={{"padding": "1rem 2rem 0.5rem", "display": "flex", "flexDirection": "column", "gap": "0.6rem"}}>
            <input
                value={query}
                placeholder="Type to search in keybindings"
                aria-label="Search keybindings"
                onChange={lambda (e: any) { query = e.target.value; }}
                style={{**FIELD_STYLE, "width": "100%"}}
            />
            <div style={{"display": "flex", "justifyContent": "space-between", "fontSize": "12px", "opacity": "0.8"}}>
                <span>{str(len(shown)) + " of " + str(len(commands)) + " commands"}</span>
                <button onClick={lambda (e: any) { onOpenJson(); }} style={LINK_STYLE}>Open Keyboard Shortcuts (JSON)</button>
            </div>
            <div style={{"display": "grid", "gridTemplateColumns": GRID, "gap": "0.75rem", "padding": "0.35rem 0.5rem", "fontSize": "12px", "fontWeight": "600", "borderBottom": "1px solid #2A2B2C", "opacity": "0.85"}}>
                <span>Command</span><span>Keybinding</span><span>When</span><span>Source</span><span />
            </div>
        </div>
        <div style={{"flex": "1", "overflow": "auto", "padding": "0 2rem 2rem"}}>
            {[
                <div key={c["id"]} style={{"borderBottom": "1px solid #1f2021"}}>
                    <div style={{"display": "grid", "gridTemplateColumns": GRID, "gap": "0.75rem", "alignItems": "center", "padding": "0.4rem 0.5rem", "fontSize": "13px"}}>
                        <span style={{"overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}} title={c["id"]}>
                            {c["title"]}
                        </span>
                        {(
                            <input
                                autoFocus={True}
                                readOnly={True}
                                data-recording-keybinding="true"
                                aria-label={"Press desired key combination for " + c["title"]}
                                value={format_keybinding([{"key": recorded, "when": ""}]) if recorded != "" else ""}
                                placeholder="Press a key combination, then Enter"
                                onKeyDown={lambda (e: any) { record_key(e); }}
                                onBlur={lambda (e: any) { cancel_recording(); }}
                                style={{**FIELD_STYLE, "borderColor": "#3794ff"}}
                            />
                        ) if editing == c["id"] else (
                            <span>
                                {[<span key={b["key"] + b["when"]} style={CHIP_STYLE}>{format_keybinding([b])}</span> for b in c["keybindings"]]}
                            </span>
                        )}
                        <span style={{"fontSize": "12px", "opacity": "0.7", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>
                            {", ".join([b["when"] for b in c["keybindings"] if b["when"] != ""])}
                        </span>
                        <span style={{"fontSize": "12px", "opacity": "0.7"}}>{"User" if c["modified"] else "Default"}</span>
                        <span style={{"display": "flex", "justifyContent": "flex-end"}}>
                            <button title="Change Keybinding" aria-label={"Change keybinding for " + c["title"]} onClick={lambda (e: any) { start_recording(c["id"]); }} style={ICON_BUTTON_STYLE}>
                                <span className="codicon codicon-edit" style={{"fontSize": "14px"}} />
                            </button>
                            <button title="Remove Keybinding" aria-label={"Remove keybinding for " + c["title"]} onClick={lambda (e: any) { clear(c["id"]); }} style={ICON_BUTTON_STYLE}>
                                <span className="codicon codicon-close" style={{"fontSize": "14px"}} />
                            </button>
                            {(
                                <button title="Reset Keybinding" aria-label={"Reset keybinding for " + c["title"]} onClick={lambda (e: any) { reset(c["id"]); }} style={ICON_BUTTON_STYLE}>
                                    <span className="codicon codicon-discard" style={{"fontSize": "14px"}} />
                                </button>
                            ) if c["modified"] else None}
                        </span>
                    </div>
                    {(
                        <div style={{"padding": "0 0.5rem 0.5rem", "fontSize": "12px"}}>
                            {(
                                <div style={{"color": "#cca700"}}>{"Also bound to: " + ", ".join(clashes)}</div>
                            ) if len(clashes) > 0 else None}
                            {(
                                <div role="alert" style={{"color": "#f48771"}}>{error}</div>
                            ) if error != "" else None}
                            <div style={{"opacity": "0.6"}}>Enter to accept, Escape to cancel. Some browser shortcuts (such as Ctrl+W) cannot be captured.</div>
                        </div>
                    ) if editing == c["id"] else None}
                </div>
                for c in shown
            ]}
            {(
                <div style={{"padding": "1rem 0.5rem", "fontSize": "13px", "opacity": "0.6"}}>No keybindings found.</div>
            ) if len(shown) == 0 else None}
        </div>
    </div>
}
