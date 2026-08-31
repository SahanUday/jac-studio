"""Outline: Phase 4's outline sidebar view (`docs/roadmap.md`), the fourth real entry in
`activity_bar.jac`'s `VIEWS`, backed by `jac lsp`'s own `textDocument/documentSymbol`
(`lsp_client.jac`'s `get_document_symbols`). This is the last item on the native LSP client's
originally-scoped work -- completion, live diagnostics, hover, go-to-definition, find-references,
and rename all shipped in earlier PRs; `roadmap.md`'s Phase 4 bullet explicitly bundles
"outline/call-hierarchy/breadcrumbs views" in with the rest as "required parts of this same effort,
not separate features discovered later." **Call-hierarchy is out of scope here, not silently
dropped**: `jac lsp` (`jaclang.lsp.server.server`) implements completion, hover, definition,
references, rename, document-symbols, semantic-tokens, and formatting -- no call-hierarchy handler
exists on the server this client talks to, so there is nothing to wire up yet; that would need its
own server-side capability first. **Breadcrumbs is a deliberate, separate follow-up PR**, not
bundled into this one -- it consumes the same `get_document_symbols` data this view does, but needs
a genuinely different piece of plumbing (live cursor position, tracking which symbol currently
contains it) layered on top, not just a second renderer over the same fetch.

**A new activity-bar entry, not an Explorer sub-section -- a deliberate simplification, not a
fidelity claim.** Real VS Code nests its Outline view inside the Explorer sidebar as a collapsible
section, not as its own top-level icon. `file_tree.jac` has no "multiple collapsible sections"
concept at all today, and building one just for this would be a bigger, separate change than the
outline feature itself. Reusing `activity_bar.jac`'s already-built `VIEWS` mechanism (built in
Phase 3 specifically so a new sidebar view is "a one-entry addition... no new plumbing," per that
module's own docstring) is the honest MVP placement -- matching real VS Code's exact chrome layout
is not what that mechanism promises.

**`active` prop refreshes on activation, the identical pattern `scm.jac` already established (and
caught live) for the same underlying problem** -- this view mounts once at workbench startup,
hidden via CSS, so a plain `can with entry` fetch would run before any file is even open and never
again. `useEffect([active, path])` re-fetches whenever the Outline tab becomes the visible one *or*
the active editor tab changes while Outline is already visible -- the second dependency has no
`scm.jac` equivalent (SCM has no "active file" concept to react to), and is this view's entire
reason to exist: show whichever file is open right now, not whichever was open when this tab was
last visited.

**Reads the file's last-saved content via `open_document`, not the live Monaco buffer -- a
deliberate v1 scope cut, matching the LSP client's own already-accepted "diagnostics only refresh
on save/completion, not per-keystroke" trade-off (`lsp_client.jac`'s own docstring).** A sidebar
view has no natural reach into a specific `MonacoEditorApp` instance's live model the way
`jac_definition_provider.jac`/etc. do -- those run *inside* an already-mounted `<Editor>`'s
`beforeMount`, with a real `monaco` instance handed to them directly; reaching for one from outside
would mean pulling in `@monaco-editor/react`'s `loader.init()` singleton-access API purely for this
one view, real added complexity for a freshness gap this client already accepts elsewhere. The
manual refresh button is the same "the action that changes state is responsible for re-fetching it"
affordance `scm.jac` already offers for its own no-file-watcher gap.

**Symbols render fully expanded, no collapse state.** Unlike `file_tree.jac`'s lazy, expand-on-
demand tree (a real, measured necessity at *workspace* scale -- see tracker entry
`2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale`), a single file's symbol outline is
small by construction; always-expanded is the honest MVP shape here, not a corner cut under time
pressure.

**Clicking a symbol reuses `open_search_result` -- the fourth reuse of that one method**, after
`search.jac`, `problems.jac`, and `jac_definition_provider.jac`'s editor opener. `get_document_symbols`
already resolves each symbol's own name-token position via `selectionRange` (not the symbol's whole
body `range`), so `(path, name, line, column)` falls out directly with no extra lookup.

Handler bodies live in the paired `outline.impl.jac` annex, per the client-component "handler
annex" pattern -- see `jac-studio-code-organization`."""

import from "react" { useEffect }
import from src.workbench.lsp.lsp_client { get_document_symbols }
import from src.editor.document_service { open_document }
import from src.workbench.symbol_icons.symbol_icons { symbol_icon_class }

def:pub OutlineNode(props: any) -> JsxElement {
    item = props["node"];
    depth = props["depth"];
    path = props["path"];
    on_open = props["onOpen"];

    <div>
        <div
            role="button"
            tabIndex={0}
            onClick={lambda (e: any) { on_open(path, path.split("/")[-1], item["line"], item["column"]); }}
            style={{
                "display": "flex",
                "alignItems": "center",
                "gap": "0.35rem",
                "padding": "0.2rem 0.5rem",
                "paddingLeft": str(8 + depth * 14) + "px",
                "fontSize": "13px",
                "fontFamily": "system-ui, sans-serif",
                "color": "#CCCCCC",
                "cursor": "pointer",
                "userSelect": "none",
                "whiteSpace": "nowrap"
            }}
        >
            <span
                className={"codicon " + symbol_icon_class(item["kind"])}
                style={{"fontSize": "14px", "opacity": "0.85", "flexShrink": "0"}}
            />
            <span style={{"overflow": "hidden", "textOverflow": "ellipsis"}}>{item["name"]}</span>
        </div>
        {[
            <OutlineNode
                key={str(depth) + ":" + child["name"] + ":" + str(child["line"])}
                node={child}
                depth={depth + 1}
                path={path}
                onOpen={on_open}
            />
            for child in item["children"]
        ]}
    </div>
}

def:pub app(active: bool, path: str, onOpenLocation: any) -> JsxElement {
    has symbols: list[dict[str, any]] = [];
    has loading: bool = False;

    async def refresh_outline -> None;

    useEffect(lambda {
        if active and path != "" {
            refresh_outline();
        }
    }, [active, path]);

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%"}}>
        <div
            style={{
                "display": "flex",
                "alignItems": "center",
                "gap": "0.4rem",
                "padding": "0.4rem 0.5rem",
                "borderBottom": "1px solid #2A2B2C",
                "fontSize": "11px",
                "textTransform": "uppercase",
                "letterSpacing": "0.04em",
                "color": "#8C8C8C",
                "fontFamily": "system-ui, sans-serif"
            }}
        >
            <span style={{"flex": "1"}}>Outline</span>
            <span
                role="button"
                title="Refresh"
                aria-label="Refresh outline"
                onClick={lambda (e: any) { refresh_outline(); }}
                className="codicon codicon-refresh"
                style={{"cursor": "pointer", "opacity": "0.85"}}
            />
        </div>
        <div style={{"flex": "1", "overflow": "auto"}}>
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    Loading...
                </div>
            ) if loading else None}
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>
                    No symbols in this file.
                </div>
            ) if (not loading and path != "" and len(symbols) == 0) else None}
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#5A5A5A", "fontFamily": "system-ui, sans-serif"}}>
                    Open a file to see its outline.
                </div>
            ) if (not loading and path == "") else None}
            {[
                <OutlineNode key={s["name"] + ":" + str(s["line"])} node={s} depth={0} path={path} onOpen={onOpenLocation} />
                for s in symbols
            ]}
        </div>
    </div>
}
