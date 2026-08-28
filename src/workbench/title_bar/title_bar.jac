"""TitleBar: the custom title bar + Command Center search box, `docs/roadmap.md`'s Phase 3 "close
the Phase 2 gap" bullet (`vscode-complete-triage.md`'s `titlebar` row, found 2026-08-28 by checking
VS Code's live `workbench/browser/parts` source directly -- completely undocumented before that
pass).

**No window controls (minimize/maximize/close) -- deliberately, not an oversight.** This is a
`kind = "web-app"` project (`jac.toml`); the browser tab already owns window chrome, the same
reason vscode.dev's own title bar has none either. `docs/architecture.md`'s layer-mapping table
defers the native desktop host (`jac nacompile` + OS webview) to a later roadmap phase -- window
controls become relevant there, not here.

**No menu bar (File/Edit/Selection/View/...) -- also deliberately out of scope.** `roadmap.md`'s
bullet names two things specifically: "the custom title bar + Command Center search box." A real
menu bar with wired dropdown commands for every upstream menu item is a materially larger feature
this bullet never asked for; the left side stays a plain app label.

**The Command Center pill opens the command palette**, not a merged file+command search. Real
VS Code's Command Center is a single input that can search files (bare text) or commands (`>`
prefix) -- jac-studio deliberately keeps these as the two genuinely separate `quickaccess`
providers `roadmap.md` already scoped them as (`command_palette.jac`, `quick_open.jac`), so the
pill's job here is just to be a second, discoverable entry point into the command palette
alongside `Ctrl+Shift+P` -- not to invent a third, unified search surface. Dispatches through
`onOpenCommandPalette`, which `workbench.jac` wires to the same `handle_command`-driven
`workbench.action.showCommands` path the keyboard shortcut now also uses (see
`command_palette.jac`'s docstring for why that shortcut moved off its own self-contained listener
to make this possible).

**Static label, not the live workspace name.** Real VS Code's Command Center shows the open
folder's name. Wiring that here would mean threading the workspace name out of `file_tree.jac`'s
own internal state up through `workbench.jac` just for this one label -- real, but separate scope
from "add a title bar," and not worth a state-lifting refactor for a label. Left as a named,
deliberate simplification, not a silently dropped requirement.

**Purely presentational, like `status_bar.jac`** -- takes one callback prop and renders, owns no
state of its own, so there's no paired `.impl.jac` annex.

**Colors follow this project's existing (pre-existing, not introduced here) dark-only convention**
-- see `activity_bar.jac`'s docstring for the same caveat; not fixed here either, for the same
reason (a cross-component pass, not a piecemeal one).
"""

def:pub app(onOpenCommandPalette: any) -> JsxElement {
    <div
        role="banner"
        style={{
            "position": "relative",
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
        <span style={{"fontSize": "12px", "color": "#8C8C8C", "flexShrink": "0"}}>jac-studio</span>
        <button
            onClick={onOpenCommandPalette}
            title="Show All Commands"
            style={{
                "position": "absolute",
                "left": "50%",
                "transform": "translateX(-50%)",
                "display": "flex",
                "alignItems": "center",
                "gap": "0.4rem",
                "width": "320px",
                "height": "22px",
                "background": "#313233",
                "border": "none",
                "borderRadius": "4px",
                "cursor": "pointer",
                "padding": "0 0.6rem",
                "color": "#8C8C8C",
                "fontSize": "12px"
            }}
        >
            <span className="codicon codicon-search" style={{"fontSize": "13px"}} />
            <span>Search files and commands</span>
        </button>
    </div>
}
