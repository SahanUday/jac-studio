"""StatusBar: Phase 2's fourth workbench-shell deliverable (`docs/roadmap.md`) -- a docked bar
that echoes the active editor's cursor position. Roadmap scope for this bullet is deliberately
narrow ("no contributions yet beyond cursor position") -- unlike the command registry, this isn't
a contribution target yet, so there's nothing here but a render of what `workbench.jac` already
computed and handed down, same "leaf reports, parent owns state" shape every other workbench-shell
piece uses.

Purely presentational, like `editor_tabs.jac` -- takes `line`/`column`/`path` and renders, owns no
state of its own, so there's no paired `.impl.jac` annex.

**Not bright blue anymore (2026-08-28, Phase 3's visual-identity bullet).** This bar used to be
hardcoded to `#007acc`, matching the classic Dark+ theme's most recognizable signature -- but
checking VS Code's actual current default theme directly (`extensions/theme-defaults/themes/
2026-dark.json` in `microsoft/vscode`, confirmed as the real default via
`ThemeSettingDefaults.COLOR_THEME_DARK` in `workbenchThemeService.ts`) found that VS Code dropped
the blue status bar as of "Dark 2026": `statusBar.background` is the same flat `#191A1B` as every
other chrome surface there, with blue (`#3994BC`) reserved only for the debugging-session state.
See `docs/architecture.md`'s Visual identity section for the full correction -- this project's
earlier assumption that "Dark+/Light+" was still VS Code's default was wrong, found while doing
this work, not assumed going in.

**Notification bell (2026-08-31, Phase 4's toast-notifications bullet)** -- `NotificationsApp`
mounts as one more flex child at the far right, matching VS Code's own bell placement at the
status bar's right edge. Still purely presentational: `notifications`/`notificationPanelOpen`/
the three callback props all just forward straight through from `workbench.jac`, which owns the
actual state (see `notifications.jac`'s own docstring for why the state lives there).
"""

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
