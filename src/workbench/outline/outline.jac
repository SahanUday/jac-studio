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

**Row chrome matches `file_tree.jac`'s `FileTreeNode` exactly (2026-09-01) -- same indent step,
padding, border-radius, and reserved chevron-width spacer even for a leaf symbol, so icons at a
given depth line up identically between the two sidebar views.** Reported live: symbol rows sat one
chevron-width further left than file-tree rows at the same nesting depth, since the original version
had no spacer for symbols with no children -- not a cosmetic nit, a real alignment break between two
views a user flips between constantly. **Collapsible, not "always expanded" anymore** -- a symbol
with children now gets the same `codicon-chevron-right`/`codicon-chevron-down` toggle file-tree
folders use, defaulting open (`expanded[id]` missing means expanded, the inverse of file-tree's
default-collapsed convention, since a single file's symbol tree is small enough that "everything
visible by default" is still the right MVP shape this module's docstring already argued for --
collapsing is now just an opt-in decluttering affordance on top of that, not a replacement for it).

**Highlights whichever row contains the live cursor position (2026-09-01), reusing
`breadcrumb_symbols.jac`'s `symbol_path_at_position` -- the same pure containment walk
`monaco_editor.impl.jac`'s breadcrumb bar already computes from, not a second implementation.**
`workbench.jac` already tracks `cursor_positions[path]` for the status bar; threading that same
`{line, column}` down here as `cursorLine`/`cursorColumn` costs no new plumbing. Matches
`file_tree.jac`'s own `is_selected` treatment (`#FFFFFF22` row background) for the same reason file
explorer highlights the open file -- a sidebar view should always show which item corresponds to
where the user actually is. Only the row actually on screen highlights; a collapsed ancestor is not
force-expanded to reveal a highlighted descendant, a deliberate v1 scope cut (real VS Code's own
Outline does auto-reveal here, real follow-up work, not silently broken -- collapsing anything is
itself brand new in this same change, so there was no pre-existing expectation to preserve).

Handler bodies live in the paired `outline.impl.jac` annex, per the client-component "handler
annex" pattern -- see `jac-studio-code-organization`."""

import from "react" { useEffect }
import from src.workbench.lsp.lsp_client { get_document_symbols }
import from src.editor.document_service { open_document }
import from src.workbench.symbol_icons.symbol_icons { symbol_icon_class }
import from src.editor.client.breadcrumb_symbols { symbol_path_at_position }

glob ROW_BASE_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.35rem",
    "cursor": "pointer",
    "fontSize": "13px",
    "fontFamily": "system-ui, sans-serif",
    "padding": "0.2rem 0.5rem",
    "borderRadius": "3px",
    "userSelect": "none",
    "whiteSpace": "nowrap"
};

def _symbol_id(item: dict[str, any]) -> str {
    return item["name"] + ":" + str(item["line"]);
}

def:pub OutlineNode(props: any) -> JsxElement {
    item = props["node"];
    depth = props["depth"];
    path = props["path"];
    on_open = props["onOpen"];
    expanded = props["expanded"];
    on_toggle = props["onToggle"];
    current_chain_ids = props["currentChainIds"];

    has_children = len(item["children"]) > 0;
    id = _symbol_id(item);
    is_open = expanded[id] if id in expanded else True;
    is_current = id in current_chain_ids;
    indent = 8 + depth * 14;

    <div role="none">
        <div
            role="button"
            tabIndex={0}
            aria-expanded={is_open if has_children else None}
            onClick={lambda (e: any) {
                if has_children {
                    on_toggle(id);
                }
                on_open(path, path.split("/")[-1], item["line"], item["column"]);
            }}
            style={{
                **ROW_BASE_STYLE,
                "paddingLeft": str(indent) + "px",
                "color": "#CCCCCC",
                "background": "#FFFFFF22" if is_current else "transparent"
            }}
        >
            <span
                className={("codicon " + ("codicon-chevron-down" if is_open else "codicon-chevron-right")) if has_children else ""}
                style={{"width": "14px", "display": "inline-block", "fontSize": "14px", "opacity": "0.75"}}
            />
            <span
                className={"codicon " + symbol_icon_class(item["kind"])}
                style={{"width": "14px", "display": "inline-block", "fontSize": "14px", "opacity": "0.85"}}
            />
            <span style={{"overflow": "hidden", "textOverflow": "ellipsis"}}>{item["name"]}</span>
        </div>
        {(
            <div role="group">
                {[
                    <OutlineNode
                        key={_symbol_id(child)}
                        node={child}
                        depth={depth + 1}
                        path={path}
                        onOpen={on_open}
                        expanded={expanded}
                        onToggle={on_toggle}
                        currentChainIds={current_chain_ids}
                    />
                    for child in item["children"]
                ]}
            </div>
        ) if (has_children and is_open) else None}
    </div>
}

def:pub app(active: bool, path: str, onOpenLocation: any, cursorLine: int, cursorColumn: int) -> JsxElement {
    has symbols: list[dict[str, any]] = [];
    has loading: bool = False;
    has expanded: dict[str, bool] = {};

    async def refresh_outline -> None;
    def toggle_symbol(id: str) -> None;

    useEffect(lambda {
        if active and path != "" {
            refresh_outline();
        }
    }, [active, path]);

    current_chain = symbol_path_at_position(symbols, cursorLine, cursorColumn);
    current_chain_ids = {_symbol_id(s) for s in current_chain};

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
                <OutlineNode
                    key={_symbol_id(s)}
                    node={s}
                    depth={0}
                    path={path}
                    onOpen={onOpenLocation}
                    expanded={expanded}
                    onToggle={toggle_symbol}
                    currentChainIds={current_chain_ids}
                />
                for s in symbols
            ]}
        </div>
    </div>
}
