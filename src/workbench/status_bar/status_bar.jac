"""StatusBar: Phase 2's fourth workbench-shell deliverable (`docs/roadmap.md`) -- a docked bar
that echoes the active editor's cursor position. Roadmap scope for this bullet is deliberately
narrow ("no contributions yet beyond cursor position") -- unlike the command registry, this isn't
a contribution target yet, so there's nothing here but a render of what `workbench.jac` already
computed and handed down, same "leaf reports, parent owns state" shape every other workbench-shell
piece uses.

Purely presentational, like `editor_tabs.jac` -- takes `line`/`column`/`path` and renders, owns no
state of its own, so there's no paired `.impl.jac` annex.
"""

def:pub app(line: int, column: int, path: str) -> JsxElement {
    <div role="status" aria-live="polite" aria-label="Editor status" style={{
        "display": "flex",
        "alignItems": "center",
        "justifyContent": "flex-end",
        "height": "22px",
        "flexShrink": "0",
        "padding": "0 0.75rem",
        "background": "#007acc",
        "color": "#ffffff",
        "fontSize": "12px",
        "fontFamily": "system-ui, sans-serif"
    }}>
        {("Ln " + str(line) + ", Col " + str(column)) if path != "" else ""}
    </div>
}
