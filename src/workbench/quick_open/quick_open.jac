"""QuickOpen: Ctrl+P fuzzy file switcher, second `quickaccess` provider beside `command_palette.jac`.
See ADR 0039. Dispatched via `workbench.jac`'s generic keybinding mechanism, not its own listener.
Files refetch on every open (`useEffect(..., [open])`), not once on mount -- the workspace's file
set can change while running.
`recent_paths` is in-memory, session-only, capped at 5 -- doesn't survive a restart, by design."""

import from "react" { useEffect }
import from components.ui.command {
    CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem
}
import from src.workbench.workspace.workspace_service { list_all_files }
import from src.workbench.file_icons.file_icons { file_icon_class }

def:pub app(open: bool, onOpenChange: any, onOpenFile: any) -> JsxElement {
    has files: list[dict[str, str]] = [];
    has recent_paths: list[str] = [];

    async def refresh_files -> None;
    def handle_select(path: str) -> None;

    useEffect(lambda {
        if open {
            refresh_files();
        }
    }, [open]);

    by_path = {f["path"]: f for f in files};
    recent_files = [by_path[p] for p in recent_paths if p in by_path];
    other_files = [f for f in files if f["path"] not in recent_paths];

    render_item = lambda (f: dict[str, str]) -> JsxElement {
        return
            <CommandItem key={f["path"]} value={f["path"]} onSelect={handle_select}>
                <span className={"codicon " + file_icon_class(f["name"], False, False)} style={{"fontSize": "14px", "opacity": "0.85", "flexShrink": "0"}} />
                <span>{f["name"]}</span>
                <span style={{"marginLeft": "0.5rem", "fontSize": "11px", "color": "#8C8C8C", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>
                    {f["path"]}
                </span>
            </CommandItem>;
    };

    <CommandDialog open={open} onOpenChange={onOpenChange}>
        <CommandInput placeholder="Search files by name..." />
        <CommandList>
            <CommandEmpty>No matching files.</CommandEmpty>
            {(
                <CommandGroup heading="recently opened">
                    {[render_item(f) for f in recent_files]}
                </CommandGroup>
            ) if len(recent_files) > 0 else None}
            <CommandGroup heading="files">
                {[render_item(f) for f in other_files]}
            </CommandGroup>
        </CommandList>
    </CommandDialog>
}
