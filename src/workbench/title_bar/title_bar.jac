"""TitleBar: menu bar, then the Command Center pill, which names the open workspace and just opens
the command palette (`onOpenCommandPalette`); it is not a merged file+command search. Hand-built,
see ADR 0040. No window controls: `kind = "web-app"`, so the browser tab owns window chrome. The menu
bar reverses 0040's menu-less choice, see ADR 0083."""

import from src.workbench.menu_bar.menu_bar { app as MenuBarApp }

def:pub app(onOpenCommandPalette: any, workspaceName: str, commands: list[dict[str, any]], hasWorkspace: bool, hasTab: bool, hasEditor: bool, onCommand: any) -> JsxElement {
    <div
        role="banner"
        style={{
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
        <div style={{"height": "100%", "flexShrink": "0"}}>
            <MenuBarApp commands={commands} hasWorkspace={hasWorkspace} hasTab={hasTab} hasEditor={hasEditor} onCommand={onCommand} />
        </div>
        <div style={{"flex": "1", "minWidth": "0", "display": "flex", "justifyContent": "center", "padding": "0 0.75rem"}}>
            <button
                onClick={onOpenCommandPalette}
                title="Show All Commands"
                style={{
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "center",
                    "gap": "0.4rem",
                    "width": "100%",
                    "maxWidth": "320px",
                    "height": "22px",
                    "background": "#313233",
                    "border": "none",
                    "borderRadius": "4px",
                    "cursor": "pointer",
                    "padding": "0 0.6rem",
                    "color": "#8C8C8C",
                    "fontSize": "12px",
                    "overflow": "hidden",
                    "whiteSpace": "nowrap"
                }}
            >
                <span className="codicon codicon-search" style={{"fontSize": "13px", "flexShrink": "0"}} />
                <span style={{"overflow": "hidden", "textOverflow": "ellipsis"}}>{workspaceName if workspaceName != "" else "jac-studio"}</span>
            </button>
        </div>
    </div>
}
