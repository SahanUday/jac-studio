"""EditorTabs: Phase 2's second workbench-shell deliverable (`docs/roadmap.md`) -- a tab bar plus
content area for open files, sitting next to `file_tree.jac`'s sidebar under a shared
`src/workbench/shell/workbench.jac` parent that owns which files are open and which is active.

**Purely presentational -- owns no state of its own.** Unlike `file_tree.jac`'s and
`text_editor.jac`'s top-level `app`s, this component takes `openTabs`/`activePath` plus
`onSelectTab`/`onCloseTab`/`onOpenTab` callbacks as props and renders from them. The state itself
lives in the shared parent (`Workbench`) because both this component and the file tree need to
read and mutate the same "which files are open" list -- lifting it to their common parent is the
standard fix for that, the same reasoning `docs/architecture.md`'s contribution-registry pattern
uses at the graph level, just applied to plain React-style prop flow here since this state is
ephemeral UI state, not graph state (see `document_service.jac`'s docstring on why the Phase 3
`EditorGroup`/`Tab` nodes aren't built yet).

**Hand-built tab row, not shadcn's `Tabs`/`TabsTrigger`.** A close ("x") button belongs inside
each tab per real-editor convention, but Radix's `TabsTrigger` renders as a `<button>`, and a
`<button>` inside a `<button>` is invalid HTML (and breaks the trigger's own click/keyboard
handling). Same call `file_tree.jac` already made for its rows against `SidebarMenuSub` -- use the
primitive where it fits, hand-roll where it doesn't.

**Every open tab's `MonacoEditorApp` stays mounted**, hidden via `display: none` rather than
conditionally rendered, so switching tabs never re-fetches content or loses Monaco's own undo
history for that file -- the whole reason this doesn't use Radix `TabsContent`, which unmounts
inactive panels by default.

**`MonacoEditorApp` (2026-08-25)**, not the archived native `TextEditorApp` -- see
`docs/architecture.md`'s Editor Core section. The mounted-per-tab shape here is unaffected by that
switch either way.

**Editor-group splitting (2026-08-25, `docs/roadmap.md` Phase 2)**: this component still renders
exactly one group's tab row + content, unaware it's one of possibly several -- `workbench.jac` owns
the list of groups and mounts one `EditorTabs` per group inside a `ResizablePanelGroup`. Rather than
handing each instance a pre-bound closure (which would mean building N distinct closures in a JSX
list -- a loop-variable-capture footgun to avoid, not a real need here), this component takes a
plain `groupId` prop and forwards it as the first argument on every callback (`onSelectTab(groupId,
path)`, `onCloseTab(groupId, path)`, `onSplitGroup(groupId)`), same "leaf reports, parent owns
identity" shape `file_tree.jac`'s `FileTreeNode` already uses for `onSelect`/`onToggle`. VS Code's
real split duplicates the *active* editor into a new group beside it, so the split button is a
no-op (still shown, per real-editor convention of always offering it) when this group has no active
tab to duplicate -- `workbench.impl.jac`'s `split_group` is where that guard lives, not here.
"""

import from src.editor.client.monaco_editor { app as MonacoEditorApp }
import from components.ui.button { Button }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { SquareSplitHorizontalIcon }

glob TAB_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.4rem",
    "padding": "0.35rem 0.5rem",
    "fontSize": "12px",
    "fontFamily": "system-ui, sans-serif",
    "cursor": "pointer",
    "userSelect": "none",
    "borderRight": "1px solid #3c3c3c",
    "whiteSpace": "nowrap"
};

def:pub app(props: any) -> JsxElement {
    group_id = props["groupId"];
    open_tabs = props["openTabs"];
    active_path = props["activePath"];
    on_select_tab = props["onSelectTab"];
    on_close_tab = props["onCloseTab"];
    on_split_group = props["onSplitGroup"];

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%", "overflow": "hidden"}}>
        <div style={{"display": "flex", "alignItems": "center", "borderBottom": "1px solid #3c3c3c", "background": "#252526", "flexShrink": "0"}}>
            <div style={{"display": "flex", "flex": "1", "overflow": "auto"}}>
                {[
                    <div
                        key={t["path"]}
                        onClick={lambda (e: any) { on_select_tab(group_id, t["path"]); }}
                        style={{
                            **TAB_STYLE,
                            "background": "#1e1e1e" if t["path"] == active_path else "transparent",
                            "color": "#d4d4d4" if t["path"] == active_path else "#969696"
                        }}
                    >
                        <span>{t["name"]}</span>
                        <span
                            onClick={lambda (e: any) { e.stopPropagation(); on_close_tab(group_id, t["path"]); }}
                            style={{"opacity": "0.6", "fontSize": "13px", "lineHeight": "1"}}
                        >
                            &times;
                        </span>
                    </div>
                    for t in open_tabs
                ]}
            </div>
            <Button
                variant="ghost"
                size="icon-sm"
                title="Split editor right"
                onClick={lambda (e: any) { on_split_group(group_id); }}
                style={{"flexShrink": "0", "marginRight": "0.25rem"}}
            >
                <HugeiconsIcon icon={SquareSplitHorizontalIcon} strokeWidth={2} className="size-4" />
            </Button>
        </div>
        <div style={{"flex": "1", "overflow": "auto", "padding": "0.75rem"}}>
            {(
                [
                    <div key={t["path"]} style={{"display": "block" if t["path"] == active_path else "none", "height": "100%"}}>
                        <MonacoEditorApp path={t["path"]} />
                    </div>
                    for t in open_tabs
                ]
            ) if len(open_tabs) > 0 else (
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#888", "fontFamily": "system-ui, sans-serif"}}>
                    No file open. Select one from the file tree.
                </div>
            )}
        </div>
    </div>
}
