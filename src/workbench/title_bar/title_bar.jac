"""TitleBar: custom title bar + Command Center search box. Hand-built, see ADR 0040.
No window controls or menu bar -- `kind = "web-app"`, so the browser tab owns window chrome.
The Command Center pill just opens the command palette (`onOpenCommandPalette`); it is not a
merged file+command search -- `command_palette.jac`/`quick_open.jac` stay separate providers.
Static app-name label, not the live workspace name (not worth a state-lifting refactor)."""

def:pub app(onOpenCommandPalette: any) -> JsxElement {
    <div
        role="banner"
        style={{
            "position": "relative",
            "display": "flex",
            "alignItems": "center",
            "height": "30px",
            "flexShrink": "0",
            "background": "#191A1B",
            "borderBottom": "1px solid #2A2B2C",
            "padding": "0 0.5rem",
            "fontFamily": "system-ui, sans-serif"
        }}
    >
        <span style={{"fontSize": "12px", "color": "#8C8C8C", "flexShrink": "0"}}>jac-studio</span>
        <button
            onClick={onOpenCommandPalette}
            title="Show All Commands"
            style={{
                "position": "absolute",
                "left": "50%",
                "transform": "translateX(-50%)",
                "display": "flex",
                "alignItems": "center",
                "gap": "0.4rem",
                "width": "320px",
                "height": "22px",
                "background": "#313233",
                "border": "none",
                "borderRadius": "4px",
                "cursor": "pointer",
                "padding": "0 0.6rem",
                "color": "#8C8C8C",
                "fontSize": "12px"
            }}
        >
            <span className="codicon codicon-search" style={{"fontSize": "13px"}} />
            <span>Search files and commands</span>
        </button>
    </div>
}
