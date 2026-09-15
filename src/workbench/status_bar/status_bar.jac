"""StatusBar: docked bar echoing the active editor's cursor position, plus the notification bell.
Purely presentational -- renders what `workbench.jac` hands down, no own state, no `.impl.jac`.
Flat `#191A1B` background, not classic VS Code blue: current default theme dropped it. See ADR 0033."""

import from src.workbench.notifications.notifications { app as NotificationsApp }

def:pub app(props: any) -> JsxElement {
    line = props["line"];
    column = props["column"];
    path = props["path"];
    notifications = props["notifications"];
    notification_panel_open = props["notificationPanelOpen"];
    on_notification_panel_change = props["onNotificationPanelChange"];
    on_dismiss_notification = props["onDismissNotification"];
    on_clear_notifications = props["onClearNotifications"];

    <div role="status" aria-live="polite" aria-label="Editor status" style={{
        "display": "flex",
        "alignItems": "center",
        "justifyContent": "flex-end",
        "height": "22px",
        "flexShrink": "0",
        "padding": "0 0.75rem",
        "background": "#191A1B",
        "color": "#8C8C8C",
        "fontSize": "12px",
        "fontFamily": "system-ui, sans-serif",
        "gap": "0.75rem"
    }}>
        <span>{("Ln " + str(line) + ", Col " + str(column)) if path != "" else ""}</span>
        <NotificationsApp
            notifications={notifications}
            open={notification_panel_open}
            onOpenChange={on_notification_panel_change}
            onDismiss={on_dismiss_notification}
            onClearAll={on_clear_notifications}
        />
    </div>
}
