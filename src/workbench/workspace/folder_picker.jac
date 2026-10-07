"""Open Folder dialog over `folder_browser.jac`; `mode` "recent" starts on the recent list, as File >
Open Recent does, with a Browse button into the directory view. `onPick(path)` closes nothing itself --
the owner decides. Handler bodies live in `folder_picker.impl.jac`."""

import from "react" { useEffect }
import from src.workbench.workspace.folder_browser { list_directories }
import from src.workbench.workspace.workbench_state { list_recent_workspaces, remove_recent_workspace }
import from components.ui.dialog { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter }
import from components.ui.button { Button }
import from components.ui.scroll_area { ScrollArea }

glob DIALOG_STYLE: dict[str, str] = {
    "fontFamily": "system-ui, sans-serif",
    "background": "#252627",
    "color": "#cccccc",
    "border": "1px solid #3C3C3C",
    "colorScheme": "dark"
};

glob SECONDARY_BUTTON_STYLE: dict[str, str] = {"background": "#3C3C3C", "color": "#cccccc", "border": "none"};

glob ROW_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.5rem",
    "width": "100%",
    "padding": "0.3rem 0.5rem",
    "borderRadius": "4px",
    "cursor": "pointer",
    "textAlign": "left",
    "background": "transparent",
    "border": "none",
    "color": "inherit",
    "fontSize": "13px"
};

def:pub app(open: bool, mode: str, onOpenChange: any, onPick: any) -> JsxElement {
    has view: str = "browse";
    has listing: dict[str, any] = {"path": "", "parent": "", "home": "", "entries": [], "error": ""};
    has path_input: str = "";
    has recent: list[dict[str, str]] = [];
    has show_hidden: bool = False;

    async def browse(path: str) -> None;
    async def load_recent -> None;
    async def forget_recent(path: str) -> None;

    useEffect(lambda {
        if not open {
            return;
        }
        view = mode;
        load_recent();
        browse(path_input);
    }, [open, mode]);

    <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="sm:max-w-xl" style={DIALOG_STYLE}>
            <DialogHeader>
                <DialogTitle style={{"color": "#e0e0e0"}}>{"Open Recent" if view == "recent" else "Open Folder"}</DialogTitle>
                <DialogDescription style={{"color": "#8C8C8C"}}>
                    {"Pick a folder you opened before, or browse for another." if view == "recent" else "Choose the folder to use as the workspace."}
                </DialogDescription>
            </DialogHeader>
            {(
                <ScrollArea style={{"height": "300px"}}>
                    {[
                        <div key={r["path"]} style={{"display": "flex", "alignItems": "center"}}>
                            <button onClick={lambda (e: any) { onPick(r["path"]); }} style={ROW_STYLE}>
                                <span className="codicon codicon-folder" style={{"fontSize": "15px", "opacity": "0.8"}} />
                                <span>{r["name"]}</span>
                                <span style={{"opacity": "0.55", "fontSize": "12px", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>{r["location"]}</span>
                            </button>
                            <span
                                role="button"
                                title="Remove from recent"
                                aria-label={"Remove " + r["name"] + " from recent"}
                                onClick={lambda (e: any) { forget_recent(r["path"]); }}
                                className="codicon codicon-close"
                                style={{"cursor": "pointer", "opacity": "0.6", "fontSize": "13px", "padding": "0 0.4rem"}}
                            />
                        </div>
                        for r in recent
                    ]}
                    {(
                        <div style={{"padding": "1rem", "fontSize": "12px", "opacity": "0.6"}}>No recent folders yet.</div>
                    ) if len(recent) == 0 else None}
                </ScrollArea>
            ) if view == "recent" else (
                <div style={{"display": "flex", "flexDirection": "column", "gap": "0.5rem"}}>
                    <div style={{"display": "flex", "gap": "0.4rem"}}>
                        <Button
                            variant="ghost" size="icon-sm" title="Parent folder" aria-label="Parent folder"
                            disabled={listing["parent"] == ""}
                            onClick={lambda (e: any) { browse(listing["parent"]); }}
                        >
                            <span className="codicon codicon-arrow-up" style={{"fontSize": "14px"}} />
                        </Button>
                        <Button
                            variant="ghost" size="icon-sm" title="Home folder" aria-label="Home folder"
                            onClick={lambda (e: any) { browse(listing["home"]); }}
                        >
                            <span className="codicon codicon-home" style={{"fontSize": "14px"}} />
                        </Button>
                        <input
                            value={path_input}
                            aria-label="Folder path"
                            onChange={lambda (e: any) { path_input = e.target.value; }}
                            onKeyDown={lambda (e: any) { if e.key == "Enter" { browse(path_input); } }}
                            style={{"flex": "1", "fontSize": "12px", "padding": "0.3rem 0.5rem", "background": "transparent", "border": "1px solid #3C3C3C", "borderRadius": "4px", "color": "inherit"}}
                        />
                    </div>
                    <ScrollArea style={{"height": "260px"}}>
                        {[
                            <button key={e["path"]} onClick={lambda (ev: any) { browse(e["path"]); }} style={ROW_STYLE}>
                                <span className="codicon codicon-folder" style={{"fontSize": "15px", "opacity": "0.8"}} />
                                <span>{e["name"]}</span>
                            </button>
                            for e in listing["entries"]
                        ]}
                        {(
                            <div style={{"padding": "1rem", "fontSize": "12px", "opacity": "0.6"}}>
                                {listing["error"] if listing["error"] != "" else "No subfolders."}
                            </div>
                        ) if len(listing["entries"]) == 0 else None}
                    </ScrollArea>
                    <label style={{"display": "flex", "alignItems": "center", "gap": "0.4rem", "fontSize": "12px", "opacity": "0.8"}}>
                        <input
                            type="checkbox"
                            checked={show_hidden}
                            onChange={lambda (e: any) { show_hidden = e.target.checked; browse(listing["path"]); }}
                        />
                        Show hidden folders
                    </label>
                </div>
            )}
            <DialogFooter style={{"background": "#1f2021", "borderTop": "1px solid #3C3C3C"}}>
                {(
                    <Button style={SECONDARY_BUTTON_STYLE} onClick={lambda (e: any) { view = "browse"; }}>Browse...</Button>
                ) if view == "recent" else None}
                <Button style={SECONDARY_BUTTON_STYLE} onClick={lambda (e: any) { onOpenChange(False); }}>Cancel</Button>
                {(
                    <Button disabled={listing["path"] == ""} onClick={lambda (e: any) { onPick(listing["path"]); }}>
                        Open
                    </Button>
                ) if view == "browse" else None}
            </DialogFooter>
        </DialogContent>
    </Dialog>
}
