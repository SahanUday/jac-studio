"""ActivityBar: the icon rail switching sidebar views, `docs/roadmap.md`'s Phase 3 "close the
Phase 2 gap" bullet (`vscode-complete-triage.md`'s `workbench/browser/parts` finding, 2026-08-28).

**No shadcn primitive covers this** -- `docs/architecture.md`'s workbench-shell mapping table calls
it out explicitly: `Sidebar` is a container, not a view-*switcher*. Hand-built, matching the same
call already made for the file tree's row renderer (`SidebarMenuSub` doesn't fit a recursive tree
either).

**Built now so Phase 4's new views have somewhere to mount, not so it does much yet.** `VIEWS`
originally had exactly one real entry (Explorer) because that's the only view container that
existed in Phase 3 -- Search and Source Control land in Phase 4 per `roadmap.md`. Rather than wait
until Phase 4 to invent the switching mechanism under time pressure, the mechanism (a plain list of
`{id, title, icon}` view-container specs, one `active_view_id` owned by `workbench.jac`, one
`onSelectView` callback) was built and wired end-to-end in Phase 3 -- **Search (2026-08-31,
`docs/roadmap.md` Phase 4) is the first real proof of that bet**: a one-entry addition to `VIEWS`
below plus one more branch in `workbench.jac`'s sidebar-content render, exactly as anticipated, no
new plumbing. `VIEWS` is a plain module-level list, not a graph-backed contribution registry like
`command_registry.jac`'s `Command`/`Contributes` -- there's no dynamic extension-loading system yet
to register into (same reasoning `command_registry.jac`'s own docstring gives for
`BUILTIN_COMMANDS` being a plain list today), so a real registry would be speculative machinery for
a need that doesn't exist until Phase 4/5's actual extension system does.

**Purely presentational, like `status_bar.jac`** -- takes `activeViewId`/`onSelectView` and
renders, owns no state of its own, so there's no paired `.impl.jac` annex.

**Real `@vscode/codicons` glyphs**, not shadcn/hugeicons -- `codicon-files` for Explorer, the exact
icon VS Code's own activity bar uses for the same view, per Phase 3's icon-set-swap bullet
(`docs/architecture.md`'s Visual identity section).

**Colors follow this project's existing (pre-existing, not introduced here) dark-only convention**
-- every other hand-styled workbench-shell piece (`file_tree.jac`, `editor_tabs.jac`,
`status_bar.jac`, `workbench.jac`'s terminal panel) hardcodes literal hex values rather than
reading the `.dark`/`:root` CSS variables `styles/global.css` defines for both themes, so none of
them actually react to `main.jac`'s theme toggle -- only the shadcn-primitive-driven chrome
(`Sidebar`, `Button`, `CommandDialog`) does. This component matches that existing pattern for
consistency rather than being the one piece that silently diverges, but the underlying gap (a
theme toggle that doesn't reach most of the visible chrome) is real and unresolved -- worth fixing
across all of these components together in one pass, not accidentally, piece by piece.

**`position: relative; zIndex: 20` on the root, found live while verifying Search's own test
plan (2026-08-31).** Same root cause as `workbench.jac`'s bottom-panel finding
(`2026-08-31-fixed-sidebar-overlaps-and-intercepts-clicks-on-bottom-panel`): the vendored
`components/ui/sidebar.jac` desktop wrapper is `position: fixed; inset-y-0; z-index: 10`, spanning
the *entire* viewport height at the left edge -- it was already known to intercept clicks below it
in the same horizontal column, but this is a second, distinct instance: it also sits *above* this
activity bar (also in that same 0-48px column, just higher up the page) with no z-index of its own
to contest it. Confirmed live via `jac browse`: `elementFromPoint` at both the Explorer *and*
Search tab's real screen coordinates resolved to a file-tree `treeitem` from that other layer, not
the tab button itself -- and this predates Search entirely (Explorer's own icon had the identical
bug, just never exposed until this verification pass actually tried clicking it at its real
coordinates instead of via an accessibility-tree ref). Same fix as the bottom panel: give this
component its own stacking context above `z-index: 10`, without touching the vendored primitive.
"""

glob VIEWS: list[dict[str, str]] = [
    {"id": "explorer", "title": "Explorer", "icon": "files"},
    {"id": "search", "title": "Search", "icon": "search"}
];

def:pub app(activeViewId: str, onSelectView: any) -> JsxElement {
    <div
        role="tablist"
        aria-label="Activity Bar"
        aria-orientation="vertical"
        style={{
            "display": "flex",
            "flexDirection": "column",
            "width": "48px",
            "flexShrink": "0",
            "background": "#191A1B",
            "borderRight": "1px solid #2A2B2C",
            "position": "relative",
            "zIndex": "20"
        }}
    >
        {[
            <button
                key={v["id"]}
                role="tab"
                aria-selected={v["id"] == activeViewId}
                title={v["title"]}
                aria-label={v["title"]}
                onClick={lambda (e: any) { onSelectView(v["id"]); }}
                style={{
                    "width": "48px",
                    "height": "48px",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "center",
                    "background": "#313233" if v["id"] == activeViewId else "transparent",
                    "border": "none",
                    "borderLeft": "2px solid " + ("#bfbfbf" if v["id"] == activeViewId else "transparent"),
                    "cursor": "pointer",
                    "padding": "0"
                }}
            >
                <span
                    className={"codicon codicon-" + v["icon"]}
                    style={{
                        "fontSize": "24px",
                        "color": "#bfbfbf" if v["id"] == activeViewId else "#8C8C8C"
                    }}
                />
            </button>
            for v in VIEWS
        ]}
    </div>
}
