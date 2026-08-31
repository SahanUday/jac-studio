"""Notifications: the toast + notification-center pair from VS Code's
`workbench/browser/parts/notifications` (`docs/vscode-complete-triage.md`'s "workbench/browser/parts"
section, found 2026-08-28 -- see `docs/architecture.md`'s Workbench Shell table, which flags this row
as having no direct shadcn primitive equivalent for the *center* half; `sonner`
(`jac install --shadcn sonner`) covers the *toast* half only).

Promoted to the front of Phase 4 (`docs/roadmap.md`) ahead of search/SCM/tasks/LSP, per this
project's own re-prioritization note: those features all need a way to report background
success/failure, and there was no UI surface for that at all before this PR.

**State lives in `workbench.jac`, not here** -- `notifications`/`notification_panel_open` follow
the same "leaf reports, parent owns state" shape every other controlled workbench dialog already
uses (`CommandPaletteApp`, `QuickOpenApp`): this component is purely presentational, taking the list
and the open/dismiss/clear callbacks as props. The reason isn't just consistency for its own sake --
Phase 4's own remaining bullets (search, SCM, task runner, LSP client) will all need to push a
notification from wherever they're mounted under `WorkbenchApp`, the same way `FileTreeApp` already
receives `onOpenFile`/`onCompareFiles`; keeping the source of truth at the top means a future feature
gets `onNotify` threaded to it the same way, not a second, competing state owner.

**The ephemeral toast pop and the persistent history are two different rendered surfaces, both
driven from the one `add_notification` call site in `workbench.impl.jac`** -- `sonner`'s own
`toast()` function is a self-contained singleton (no props/context needed to call it from anywhere
`<Toaster/>` is mounted once), so `workbench.impl.jac` calls it directly at the same point it appends
to the `notifications` list, rather than this component re-deriving "a new item arrived" from a
list diff. This module only renders the *history* half: the status-bar bell (badge = current
history count -- VS Code's own bell badge is also just an unread count, not a separate unread/read
model this project has any consumer for yet) and the flyout panel listing every notification with
its severity icon, message, source, and a per-item dismiss button, via the shadcn `Sheet` primitive
(side="right", matching VS Code's own notification-center placement) rather than a hand-rolled
overlay.

**Hand-styled hex chrome, not shadcn's `Button`/CSS-variable palette, for the bell trigger itself**
-- matches `status_bar.jac`'s own convention (this component mounts *inside* the status bar), and
the same acknowledged-but-not-yet-fixed inconsistency `activity_bar.jac`'s docstring already
documents for every other hand-built piece of chrome. The flyout panel's *content* (header, list,
footer) uses real shadcn `Sheet*` parts, same as `command_palette.jac` composes `Dialog`/`Command` --
only the always-visible trigger needs to match its hex-styled status-bar neighbors.
"""

import from components.ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetFooter }

glob _SEVERITY_ICONS: dict[str, str] = {
    "error": "error",
    "warning": "warning",
    "info": "info"
};

glob _SEVERITY_COLORS: dict[str, str] = {
    "error": "#F85149",
    "warning": "#D29922",
    "info": "#3994BC"
};

def:pub app(
    notifications: list[dict[str, any]],
    open: bool,
    onOpenChange: any,
    onDismiss: any,
    onClearAll: any
) -> JsxElement {
    count = len(notifications);

    <>
        <button
            aria-label={f"Notifications ({count})" if count > 0 else "Notifications"}
            title="Notifications"
            onClick={lambda (e: any) { onOpenChange(not open); }}
            style={{
                "display": "flex",
                "alignItems": "center",
                "gap": "0.25rem",
                "height": "22px",
                "padding": "0 0.5rem",
                "background": "transparent",
                "border": "none",
                "color": "#8C8C8C",
                "fontSize": "12px",
                "fontFamily": "system-ui, sans-serif",
                "cursor": "pointer"
            }}
        >
            <span
                className={"codicon " + ("codicon-bell-dot" if count > 0 else "codicon-bell")}
                style={{"fontSize": "14px"}}
            />
            {(str(count)) if count > 0 else None}
        </button>
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent side="right" className="w-80 sm:max-w-80">
                <SheetHeader>
                    <SheetTitle>Notifications</SheetTitle>
                    <SheetDescription>
                        {(str(count) + " notification" + ("s" if count != 1 else "")) if count > 0 else "No new notifications"}
                    </SheetDescription>
                </SheetHeader>
                <div style={{"flex": "1", "overflowY": "auto", "padding": "0 1rem", "display": "flex", "flexDirection": "column", "gap": "0.5rem"}}>
                    {[
                        <div
                            key={n["id"]}
                            style={{
                                "display": "flex",
                                "gap": "0.5rem",
                                "padding": "0.5rem",
                                "border": "1px solid #2A2B2C",
                                "borderRadius": "6px",
                                "background": "#191A1B"
                            }}
                        >
                            <span
                                className={"codicon codicon-" + _SEVERITY_ICONS.get(n["severity"], "info")}
                                style={{"fontSize": "16px", "color": _SEVERITY_COLORS.get(n["severity"], "#8C8C8C"), "flexShrink": "0"}}
                            />
                            <div style={{"flex": "1", "minWidth": "0"}}>
                                <div style={{"fontSize": "13px", "color": "#CCCCCC"}}>{n["message"]}</div>
                                {(<div style={{"fontSize": "11px", "color": "#8C8C8C", "marginTop": "0.15rem"}}>{n["source"]}</div>) if n["source"] else None}
                            </div>
                            <button
                                aria-label={"Dismiss notification: " + n["message"]}
                                onClick={lambda (e: any) { onDismiss(n["id"]); }}
                                className="codicon codicon-close"
                                style={{"background": "transparent", "border": "none", "color": "#8C8C8C", "cursor": "pointer", "fontSize": "12px", "flexShrink": "0", "alignSelf": "flex-start"}}
                            />
                        </div>
                        for n in notifications
                    ]}
                </div>
                <SheetFooter>
                    <button
                        onClick={lambda (e: any) { onClearAll(); }}
                        disabled={count == 0}
                        style={{
                            "width": "100%",
                            "padding": "0.4rem",
                            "background": "transparent",
                            "border": "1px solid #2A2B2C",
                            "borderRadius": "6px",
                            "color": "#CCCCCC" if count > 0 else "#5A5A5A",
                            "fontSize": "12px",
                            "cursor": "pointer" if count > 0 else "default"
                        }}
                    >
                        Clear All
                    </button>
                </SheetFooter>
            </SheetContent>
        </Sheet>
    </>
}
