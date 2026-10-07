"""StatusBar: branch and problem counts on the left; on the right the active editor's cursor,
indentation, encoding, line ending and language, then the notification bell. Indentation, line ending
and language open pickers that change the active editor's model only (nothing is saved to settings).
Branch and problems are polled; editor details are read from Monaco on each render, which cursor
movement already triggers. Flat `#191A1B`, not classic VS Code blue: ADR 0033. Handlers live in
`status_bar.impl.jac`."""

import from "react" { useEffect }
import from src.workbench.notifications.notifications { app as NotificationsApp }
import from src.workbench.scm.git_service { get_git_branch }
import from src.workbench.diagnostics.diagnostics { get_diagnostic_counts }
import from src.editor.client.monaco_editor { get_editor_status, set_editor_option, list_editor_languages }
import from components.ui.dropdown_menu {
    DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuCheckboxItem,
    DropdownMenuLabel, DropdownMenuSeparator
}

glob POLL_MS: int = 4000;

glob ITEM_STYLE: dict[str, str] = {
    "background": "none", "border": "none", "color": "inherit", "cursor": "pointer",
    "fontSize": "12px", "padding": "0 0.35rem", "height": "100%", "display": "flex", "alignItems": "center", "gap": "0.3rem"
};

glob TAB_SIZES: list[int] = [2, 4, 8];

def:pub app(props: any) -> JsxElement {
    has branch: str = "";
    has counts: dict[str, int] = {"error": 0, "warning": 0};
    has languages: list[dict[str, str]] = [];
    has tick: int = 0;

    line = props["line"];
    column = props["column"];
    path = props["path"];
    has_editor = props["hasEditor"];
    has_workspace = props["hasWorkspace"];
    on_command = props["onCommand"];
    notifications = props["notifications"];
    notification_panel_open = props["notificationPanelOpen"];
    on_notification_panel_change = props["onNotificationPanelChange"];
    on_dismiss_notification = props["onDismissNotification"];
    on_clear_notifications = props["onClearNotifications"];

    async def poll -> None;
    async def choose(kind: str, value: any) -> None;
    async def load_languages -> None;

    useEffect(lambda {
        if not has_workspace {
            branch = "";
            counts = {"error": 0, "warning": 0};
            return;
        }
        poll();
        timer = setInterval(lambda { poll(); }, POLL_MS);
        return lambda { clearInterval(timer); };
    }, [has_workspace]);

    info = get_editor_status(path) if has_editor else None;

    <div role="status" aria-live="polite" aria-label="Editor status" style={{
        "display": "flex",
        "alignItems": "center",
        "height": "22px",
        "flexShrink": "0",
        "padding": "0 0.4rem",
        "background": "#191A1B",
        "color": "#8C8C8C",
        "fontSize": "12px",
        "fontFamily": "system-ui, sans-serif"
    }}>
        {(
            <button title="Source Control" onClick={lambda (e: any) { on_command("workbench.action.showScm"); }} style={ITEM_STYLE}>
                <span className="codicon codicon-git-branch" style={{"fontSize": "13px"}} />
                <span>{branch}</span>
            </button>
        ) if branch != "" else None}
        {(
            <button title="Problems" aria-label={str(counts["error"]) + " errors, " + str(counts["warning"]) + " warnings"} onClick={lambda (e: any) { on_command("workbench.actions.view.problems"); }} style={ITEM_STYLE}>
                <span className="codicon codicon-error" style={{"fontSize": "13px"}} />
                <span>{str(counts["error"])}</span>
                <span className="codicon codicon-warning" style={{"fontSize": "13px"}} />
                <span>{str(counts["warning"])}</span>
            </button>
        ) if has_workspace else None}
        <span style={{"flex": "1"}} />
        {(
            <button title="Go to Line/Column" onClick={lambda (e: any) { on_command("editor.action.gotoLine"); }} style={ITEM_STYLE}>
                {"Ln " + str(line) + ", Col " + str(column)}
            </button>
        ) if info is not None else None}
        {(
            <DropdownMenu>
                <DropdownMenuTrigger asChild={True}>
                    <button title="Select Indentation" aria-label="Select Indentation" style={ITEM_STYLE}>
                        {("Spaces: " if info["insertSpaces"] else "Tab Size: ") + str(info["tabSize"])}
                    </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent className="dark" side="top" align="end" style={{"minWidth": "180px", "width": "auto"}}>
                    <DropdownMenuLabel>Indent Using</DropdownMenuLabel>
                    <DropdownMenuCheckboxItem checked={info["insertSpaces"]} onCheckedChange={lambda (c: any) { choose("indent", {"insertSpaces": True, "tabSize": info["tabSize"]}); }}>Spaces</DropdownMenuCheckboxItem>
                    <DropdownMenuCheckboxItem checked={not info["insertSpaces"]} onCheckedChange={lambda (c: any) { choose("indent", {"insertSpaces": False, "tabSize": info["tabSize"]}); }}>Tabs</DropdownMenuCheckboxItem>
                    <DropdownMenuSeparator />
                    <DropdownMenuLabel>Tab Size</DropdownMenuLabel>
                    {[
                        <DropdownMenuCheckboxItem key={str(n)} checked={info["tabSize"] == n} onCheckedChange={lambda (c: any) { choose("indent", {"insertSpaces": info["insertSpaces"], "tabSize": n}); }}>{str(n)}</DropdownMenuCheckboxItem>
                        for n in TAB_SIZES
                    ]}
                </DropdownMenuContent>
            </DropdownMenu>
        ) if info is not None else None}
        {(
            <span title="Encoding" style={{**ITEM_STYLE, "cursor": "default"}}>UTF-8</span>
        ) if info is not None else None}
        {(
            <DropdownMenu>
                <DropdownMenuTrigger asChild={True}>
                    <button title="Select End of Line Sequence" aria-label="Select End of Line Sequence" style={ITEM_STYLE}>{info["eol"]}</button>
                </DropdownMenuTrigger>
                <DropdownMenuContent className="dark" side="top" align="end" style={{"minWidth": "140px", "width": "auto"}}>
                    {[
                        <DropdownMenuCheckboxItem key={e} checked={info["eol"] == e} onCheckedChange={lambda (c: any) { choose("eol", e); }}>{e}</DropdownMenuCheckboxItem>
                        for e in ["LF", "CRLF"]
                    ]}
                </DropdownMenuContent>
            </DropdownMenu>
        ) if info is not None else None}
        {(
            <DropdownMenu onOpenChange={lambda (o: bool) { if o { load_languages(); } }}>
                <DropdownMenuTrigger asChild={True}>
                    <button title="Select Language Mode" aria-label="Select Language Mode" style={ITEM_STYLE}>{info["languageName"]}</button>
                </DropdownMenuTrigger>
                <DropdownMenuContent className="dark" side="top" align="end" style={{"minWidth": "200px", "width": "auto", "maxHeight": "360px"}}>
                    {[
                        <DropdownMenuCheckboxItem key={l["id"]} checked={info["language"] == l["id"]} onCheckedChange={lambda (c: any) { choose("language", l["id"]); }}>{l["name"]}</DropdownMenuCheckboxItem>
                        for l in languages
                    ]}
                </DropdownMenuContent>
            </DropdownMenu>
        ) if info is not None else None}
        <NotificationsApp
            notifications={notifications}
            open={notification_panel_open}
            onOpenChange={on_notification_panel_change}
            onDismiss={on_dismiss_notification}
            onClearAll={on_clear_notifications}
        />
    </div>
}
