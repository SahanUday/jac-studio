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

**Cursor position (2026-08-25, `docs/roadmap.md` Phase 2)**: `onCursorChange` is forwarded to
every mounted `MonacoEditorApp` unmodified -- unlike `onSelectTab`/`onCloseTab`/`onSplitGroup`, it
doesn't need `groupId` threaded in, since `MonacoEditorApp` already reports its own `path`, which
uniquely identifies the tab regardless of which group it's in. `initialCursors` (2026-08-28, Phase 3
session restore) is looked up per-tab by `path` and forwarded as each `MonacoEditorApp`'s
`initialCursor` prop -- `None` for an ordinarily-opened tab with no restored position, matching that
prop's own documented default.

**Diff tabs (2026-08-28, `docs/roadmap.md` Phase 3)** -- a tab whose dict carries `"kind": "diff"`
(alongside `"originalPath"`/`"modifiedPath"`, from `workbench.impl.jac`'s `open_diff_tab`) renders
`MonacoDiffEditorApp` instead of `MonacoEditorApp` for its content panel. An ordinary tab's dict has
no `"kind"` key at all, so `t.get("kind") == "diff"` is the one branch point -- no other change to
this component's tab-bar rendering (the label, close button, and tab-row chrome are identical for a
diff tab, matching real-editor convention of showing a diff view as just another tab).

**Git diff tabs (2026-08-31, `docs/roadmap.md` Phase 4's SCM bullet)** -- a second, distinct `"kind":
"gitdiff"` (alongside `"filePath"`/`"staged"`, from `workbench.impl.jac`'s `open_scm_diff`) renders
`ScmDiffEditorApp` instead. Deliberately not folded into `"diff"`'s existing branch even though both
render *a* Monaco diff editor: `"diff"` carries two real on-disk paths `MonacoDiffEditorApp` loads
itself via `document_service`, while `"gitdiff"` carries a single file path plus a staged/unstaged
flag that `ScmDiffEditorApp` resolves into content via `git_service.get_diff_content` -- different
enough inputs that a shared branch would need to smuggle a discriminant through anyway. Both share
the same fixed `codicon-diff` tab icon.

**Icon set and colors (2026-08-28, Phase 3's visual-identity bullet)**: the split-editor icon moved
from `@hugeicons/react` to a real `@vscode/codicons` glyph (`codicon-split-horizontal`), the same
icon font VS Code itself ships, and the tab-close "x" moved from a literal `&times;` character to
`codicon-close`, for the same reason. Tab bar/row colors were hand-corrected to VS Code's actual
current default theme ("Dark 2026", not "Dark+" -- see `docs/architecture.md`'s Visual identity
section for why that distinction matters).

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

**Tab affordances (2026-08-28, `docs/roadmap.md` Phase 3, the last item on the phase's list)** --
two additions, both purely presentational like everything else in this file:

- **File-type icon**: each tab now shows the same `file_icons.jac`-derived glyph
  `file_tree.jac`'s rows use, keyed off the tab's `name` (the real filename for an ordinary tab).
  A diff tab (`t.get("kind") == "diff"`) gets a fixed `codicon-diff` glyph instead -- its `name` is
  a combined `"a ↔ b"` display string, not a real filename, so running it through the extension-
  bucketing helper would be meaningless.
- **Unsaved-changes indicator**: `dirtyPaths` (a `dict[str, bool]`, forwarded from `workbench.jac`,
  which is in turn fed by `monaco_editor.jac`'s new `onDirtyChange` report) drives a dot-vs-close-
  button swap matching real VS Code's own tab convention -- a dirty tab shows a filled dot
  (`codicon-circle-filled`) in place of the close "x" by default, and the dot fades out in favor of
  the close "x" on hover so the tab can still be closed without saving first. Built with Tailwind's
  `group`/`group-hover:` utilities (already used elsewhere in this project's shadcn-generated
  primitives, e.g. `components/ui/sidebar.jac`) rather than JS-tracked hover state, since the
  show/hide-on-hover behavior is pure CSS and doesn't need a re-render to drive it. A clean tab's
  close button is unchanged -- always visible, exactly as before this bullet.

**Go-to-definition (2026-08-31, `docs/roadmap.md` Phase 4's native LSP client bullet)** --
`onOpenLocation` is forwarded to every mounted `MonacoEditorApp` unmodified, the same "leaf
reports, parent owns identity" shape `onCursorChange`/`onDirtyChange` already use. It's really
`workbench.jac`'s `open_search_result` (the same handler `problems.jac`/`search.jac` already reuse
for "open or activate this file's tab and jump to a line/column"), which is what lets a definition
in a file whose tab isn't currently open or active still navigate correctly -- see
`jac_definition_provider.jac`'s own docstring for why Monaco needs this threaded in at all.

**AI code actions (2026-09-04)** -- `onAskAI` is forwarded the same unmodified way, ultimately
`workbench.jac`'s own handler that switches to the Claude Code sidebar and hands it a prompt. See
`ai_code_action_provider.jac`'s own docstring for the full design.

  **Opacity-based, not `display`-based -- caught live, not by reading either library's docs.**
  The first version used Tailwind's `hidden`/`group-hover:inline-flex` (toggling `display`), which
  compiled and rendered with no error but never actually hid anything: `@vscode/codicons`' own
  base rule, `.codicon[class*='codicon-']{display:inline-block}`, carries specificity `(0,2,0)`
  (one class plus one attribute selector) against Tailwind's plain single-class `.hidden{display:
  none}` at `(0,1,0)` -- the codicon rule wins regardless of source order, on *any* element that
  carries both a `codicon-*` class and a `display`-toggling utility class. Confirmed in isolation
  (`jac browse eval`, a bare test element with only `codicon codicon-close hidden` computed to
  `display: inline-block`, not `none`) before changing anything. The fix swaps to opacity +
  `pointer-events` (`opacity-0 pointer-events-none group-hover:opacity-60
  group-hover:pointer-events-auto`) -- properties the codicon rule never touches, so there's no
  specificity fight to lose. Not filed as a tracker entry: this is a collision between two
  third-party CSS files this project happens to combine, not a Jac/jaseci defect.
"""

import from src.editor.client.monaco_editor { app as MonacoEditorApp }
import from src.editor.client.monaco_diff_editor { app as MonacoDiffEditorApp }
import from src.workbench.scm.scm_diff_editor { app as ScmDiffEditorApp }
import from components.ui.button { Button }
import from src.workbench.file_icons.file_icons { file_icon_class }

"""Jac's comprehension grammar doesn't support tuple-unpacking loop targets (`for i, t in
enumerate(...)` fails to parse), so tab/panel DOM ids are derived from the path itself rather than
a loop index -- safe since `open_tabs` never holds two entries for the same path. Used raw, not
character-sanitized: HTML5's `id` grammar only forbids whitespace, which file paths never contain,
and per-character comprehensions here compile to `path.map(...)` client-side -- a crash, since JS
strings (unlike Python's) have no `.map`."""
def _tab_dom_id(group_id: str, path: str) -> str {
    return "tab-" + group_id + "-" + path;
}

glob TAB_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.4rem",
    "padding": "0.35rem 0.5rem",
    "fontSize": "12px",
    "fontFamily": "system-ui, sans-serif",
    "cursor": "pointer",
    "userSelect": "none",
    "borderRight": "1px solid #2A2B2C",
    "whiteSpace": "nowrap"
};

def:pub app(props: any) -> JsxElement {
    group_id = props["groupId"];
    open_tabs = props["openTabs"];
    active_path = props["activePath"];
    on_select_tab = props["onSelectTab"];
    on_close_tab = props["onCloseTab"];
    on_split_group = props["onSplitGroup"];
    on_cursor_change = props["onCursorChange"];
    initial_cursors = props["initialCursors"];
    dirty_paths = props["dirtyPaths"];
    on_dirty_change = props["onDirtyChange"];
    on_open_location = props["onOpenLocation"];
    on_open_command_palette = props["onOpenCommandPalette"];
    on_ask_ai = props["onAskAI"];

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%", "overflow": "hidden"}}>
        <div role="tablist" aria-label="Open editors" style={{"display": "flex", "alignItems": "center", "borderBottom": "1px solid #2A2B2C", "background": "#191A1B", "flexShrink": "0"}}>
            <div style={{"display": "flex", "flex": "1", "overflow": "auto"}}>
                {[
                    <div
                        key={t["path"]}
                        id={_tab_dom_id(group_id, t["path"])}
                        role="tab"
                        aria-selected={t["path"] == active_path}
                        aria-controls={"panel-" + _tab_dom_id(group_id, t["path"])}
                        tabIndex={0 if t["path"] == active_path else -1}
                        onClick={lambda (e: any) { on_select_tab(group_id, t["path"]); }}
                        className="group"
                        style={{
                            **TAB_STYLE,
                            "background": "#121314" if t["path"] == active_path else "transparent",
                            "color": "#bfbfbf" if t["path"] == active_path else "#8C8C8C"
                        }}
                    >
                        <span
                            className={"codicon " + ("codicon-diff" if t.get("kind") in ["diff", "gitdiff"] else file_icon_class(t["name"], False, False))}
                            style={{"fontSize": "14px", "opacity": "0.85"}}
                        />
                        <span>{t["name"]}</span>
                        {(
                            <span
                                className="codicon codicon-circle-filled opacity-80 group-hover:opacity-0 transition-opacity"
                                style={{"fontSize": "10px", "lineHeight": "1"}}
                            />
                        ) if dirty_paths.get(t["path"], False) else None}
                        <span
                            role="button"
                            aria-label={"Close " + t["name"]}
                            onClick={lambda (e: any) { e.stopPropagation(); on_close_tab(group_id, t["path"]); }}
                            className={"codicon codicon-close transition-opacity " + ("opacity-0 pointer-events-none group-hover:opacity-60 group-hover:pointer-events-auto" if dirty_paths.get(t["path"], False) else "opacity-60")}
                            style={{"fontSize": "13px", "lineHeight": "1"}}
                        />
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
                <span className="codicon codicon-split-horizontal" style={{"fontSize": "16px"}} />
            </Button>
        </div>
        <div style={{"flex": "1", "overflow": "auto", "padding": "0.75rem"}}>
            {(
                [
                    <div
                        key={t["path"]}
                        id={"panel-" + _tab_dom_id(group_id, t["path"])}
                        role="tabpanel"
                        aria-labelledby={_tab_dom_id(group_id, t["path"])}
                        style={{"display": "block" if t["path"] == active_path else "none", "height": "100%"}}
                    >
                        {(
                            <MonacoDiffEditorApp originalPath={t["originalPath"]} modifiedPath={t["modifiedPath"]} />
                        ) if t.get("kind") == "diff" else (
                            <ScmDiffEditorApp filePath={t["filePath"]} staged={t["staged"]} />
                        ) if t.get("kind") == "gitdiff" else (
                            <MonacoEditorApp
                                path={t["path"]}
                                onCursorChange={on_cursor_change}
                                initialCursor={initial_cursors[t["path"]] if t["path"] in initial_cursors else None}
                                onDirtyChange={on_dirty_change}
                                onOpenLocation={on_open_location}
                                onOpenCommandPalette={on_open_command_palette}
                                onAskAI={on_ask_ai}
                            />
                        )}
                    </div>
                    for t in open_tabs
                ]
            ) if len(open_tabs) > 0 else (
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    No file open. Select one from the file tree.
                </div>
            )}
        </div>
    </div>
}
