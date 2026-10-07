"""The Welcome tab: Start actions, Recent workspaces and Walkthroughs, with a startup toggle. Only
actions that exist are listed. Refetches on activation since tabs mount once and hide with CSS.
Handler bodies live in `welcome.impl.jac`."""

import from "react" { useEffect }
import from src.workbench.workspace.workbench_state {
    list_recent_workspaces, get_show_welcome, set_show_welcome
}

glob RECENT_SHOWN: int = 5;

glob LINK_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.6rem",
    "background": "none",
    "border": "none",
    "padding": "0.3rem 0",
    "color": "#3794ff",
    "fontSize": "13px",
    "cursor": "pointer",
    "textAlign": "left"
};

glob HEADING_STYLE: dict[str, str] = {"fontSize": "18px", "fontWeight": "500", "margin": "0 0 0.6rem"};

glob START_ACTIONS: list[dict[str, str]] = [
    {"command": "workbench.action.files.openFolder", "icon": "codicon-folder-opened", "label": "Open Folder..."},
    {"command": "workbench.action.openRecent", "icon": "codicon-history", "label": "Open Recent..."},
    {"command": "workbench.action.quickOpen", "icon": "codicon-go-to-file", "label": "Go to File..."},
    {"command": "workbench.action.showCommands", "icon": "codicon-terminal", "label": "Show All Commands"}
];

glob WALKTHROUGHS: list[dict[str, str]] = [
    {
        "command": "workbench.action.showCommands", "icon": "codicon-star-full",
        "title": "Get started with jac-studio", "detail": "Find any command from the palette and learn the basics."
    },
    {
        "command": "workbench.action.showSearch", "icon": "codicon-search",
        "title": "Search your workspace", "detail": ""
    },
    {
        "command": "workbench.action.showScm", "icon": "codicon-source-control",
        "title": "Review changes in Source Control", "detail": ""
    },
    {
        "command": "workbench.action.tasks.runTask", "icon": "codicon-play",
        "title": "Run a task", "detail": ""
    }
];

def:pub app(active: bool, onCommand: any, onOpenRecent: any) -> JsxElement {
    has recent: list[dict[str, str]] = [];
    has show_on_startup: bool = True;

    async def refresh -> None;
    async def toggle_show_on_startup(next_value: bool) -> None;

    useEffect(lambda {
        if active {
            refresh();
        }
    }, [active]);

    <div style={{"height": "100%", "overflow": "auto", "padding": "3rem 4rem", "fontFamily": "system-ui, sans-serif", "color": "#cccccc", "colorScheme": "dark"}}>
        <div style={{"maxWidth": "1000px", "margin": "0 auto"}}>
            <h1 style={{"fontSize": "32px", "fontWeight": "500", "margin": "2rem 0 0.2rem"}}>jac-studio</h1>
            <div style={{"fontSize": "20px", "opacity": "0.6", "marginBottom": "2.5rem"}}>Editing evolved, AI-first</div>
            <div style={{"display": "flex", "gap": "4rem", "flexWrap": "wrap"}}>
                <div style={{"flex": "1", "minWidth": "280px"}}>
                    <h2 style={HEADING_STYLE}>Start</h2>
                    {[
                        <button key={a["command"]} onClick={lambda (e: any) { onCommand(a["command"]); }} style={LINK_STYLE}>
                            <span className={"codicon " + a["icon"]} style={{"fontSize": "18px"}} />
                            <span>{a["label"]}</span>
                        </button>
                        for a in START_ACTIONS
                    ]}
                    <h2 style={{**HEADING_STYLE, "marginTop": "2rem"}}>Recent</h2>
                    {[
                        <div key={r["path"]} style={{"display": "flex", "gap": "1rem", "alignItems": "baseline", "padding": "0.15rem 0"}}>
                            <button onClick={lambda (e: any) { onOpenRecent(r["path"]); }} style={{**LINK_STYLE, "padding": "0"}}>{r["name"]}</button>
                            <span style={{"opacity": "0.55", "fontSize": "12px"}}>{r["location"]}</span>
                        </div>
                        for r in recent[:RECENT_SHOWN]
                    ]}
                    {(
                        <div style={{"fontSize": "13px", "opacity": "0.6"}}>No recent folders.</div>
                    ) if len(recent) == 0 else None}
                    {(
                        <button onClick={lambda (e: any) { onCommand("workbench.action.openRecent"); }} style={{**LINK_STYLE, "marginTop": "0.4rem"}}>More...</button>
                    ) if len(recent) > RECENT_SHOWN else None}
                </div>
                <div style={{"flex": "1", "minWidth": "280px"}}>
                    <h2 style={HEADING_STYLE}>Walkthroughs</h2>
                    {[
                        <button
                            key={w["title"]}
                            onClick={lambda (e: any) { onCommand(w["command"]); }}
                            style={{
                                "display": "flex", "alignItems": "center", "gap": "0.8rem", "width": "100%", "textAlign": "left",
                                "background": "#2a2d2e", "border": "none", "borderRadius": "6px", "padding": "0.8rem 1rem",
                                "marginBottom": "0.6rem", "color": "inherit", "cursor": "pointer"
                            }}
                        >
                            <span className={"codicon " + w["icon"]} style={{"fontSize": "20px", "color": "#3794ff"}} />
                            <span style={{"display": "flex", "flexDirection": "column", "gap": "0.2rem"}}>
                                <span style={{"fontSize": "13px", "fontWeight": "600"}}>{w["title"]}</span>
                                {(<span style={{"fontSize": "12px", "opacity": "0.7"}}>{w["detail"]}</span>) if w["detail"] != "" else None}
                            </span>
                        </button>
                        for w in WALKTHROUGHS
                    ]}
                </div>
            </div>
            <label style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "justifyContent": "center", "marginTop": "4rem", "fontSize": "13px"}}>
                <input
                    type="checkbox"
                    checked={show_on_startup}
                    onChange={lambda (e: any) { toggle_show_on_startup(e.target.checked); }}
                />
                Show welcome page on startup
            </label>
        </div>
    </div>
}
