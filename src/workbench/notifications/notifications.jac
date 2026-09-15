"""Notifications: status-bar bell + flyout history panel; `sonner` (mounted elsewhere) covers the
ephemeral toast half, this renders the persistent history only.
State lives in `workbench.jac`, not here -- purely presentational, same "leaf reports, parent owns
state" shape as other controlled dialogs.
Bell trigger is hand-styled hex to match `status_bar.jac`; flyout content uses real shadcn `Sheet*`."""

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
