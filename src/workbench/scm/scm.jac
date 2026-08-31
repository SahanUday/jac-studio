"""Scm: Phase 4's source-control sidebar view (`docs/roadmap.md`) -- the third real entry in
`activity_bar.jac`'s `VIEWS`, mounted mount-once-hide-via-CSS alongside `FileTreeApp`/`SearchApp`
(`workbench.jac`'s own established convention for a stateful sidebar view since Search landed).

**A provider-agnostic shell over one real provider, matching the roadmap's own framing** -- this
component only ever talks to `git_service.jac`'s functions, never a shell command directly; a
second VCS provider later would mean swapping the import, not restructuring this view.

**Three flat sections (Staged / Changes / Untracked), not a single mixed list** -- mirrors
`git_service.jac`'s own `get_scm_status` response shape (`{"staged", "unstaged", "untracked"}`)
directly, the same "render the service's own grouping, don't re-derive it" call `search.jac`
already made for its file-grouped results.

**No file-watcher-driven live refresh (deliberate v1 scope, matching `file_tree.jac`'s own lack of
one).** `refresh_status` is called after every mutating action this view itself performs (stage/
unstage/discard/commit) plus a manual refresh button, the same "the action that changes state is
responsible for re-fetching it" shape `file_tree.jac`'s context-menu operations already use
(`refresh_children` after create/rename/delete) -- a change made *outside* the app (editing a file
in another program, a `git` command run in the integrated terminal) won't appear until the next
manual refresh or app action. A real file-watcher is a bigger, separate feature (this project has
none yet, for any view), not a corner silently cut for SCM specifically.

**`active` prop refreshes on activation -- caught live, not assumed (2026-08-31).** This view mounts
once at workbench startup, hidden via CSS, the same "mount once, hide via CSS" convention every
other stateful sidebar view uses -- which means a plain `can with entry` fetch (this component's
first version) fires at that very first mount, *before* the user has opened any folder at all, and
never again: switching to the Source Control tab later showed a permanently stale "No repository"
even after opening a real git repo through the Explorer. Confirmed live (`jac browse`): the
`get_scm_status` endpoint itself returned correct, real data when called directly -- the bug was
purely this component never re-asking. Fixed the same way `output.jac` already solves the identical
"mounted early, needs fresh data whenever actually shown" problem: an `active` prop
(`workbench.jac` passes `active_view_id == "scm"`) drives a `useEffect([active])` that refreshes
once whenever this view becomes the visible one, not just at first mount.

**Clicking a file row opens a diff, not the plain file** -- the entire point of the SCM view is
"what changed," so `onOpenDiff(path, name, staged)` (not a plain `onOpenFile`) is the one click
action every row shares, whether staged or unstaged. See `scm_diff_editor.jac`'s own docstring for
how that diff is actually rendered.

**`confirm()` before discard, no confirmation before stage/unstage/commit** -- discarding a
working-tree change is the one irreversible action here (matches real VS Code's own "Discard
Changes" confirmation dialog); staging/unstaging/committing are all either reversible or already
require deliberately typing a commit message, so an extra dialog would just be friction, the same
calibration `file_tree.jac`'s delete-vs-rename confirmation already applies.

Handler bodies live in the paired `scm.impl.jac` annex, per the client-component "handler annex"
pattern -- see `jac-studio-code-organization`.
"""

import from "react" { useEffect }
import from src.workbench.scm.git_service {
    get_scm_status, stage_path, unstage_path, discard_path, stage_all, unstage_all, commit_changes
}
import from src.workbench.file_icons.file_icons { file_icon_class }
import from components.ui.button { Button }
import from components.ui.textarea { Textarea }

glob _EMPTY_STATUS: dict[str, any] = {
    "is_repo": False, "branch": "", "staged": [], "unstaged": [], "untracked": []
};

glob ROW_STYLE: dict[str, str] = {
    "display": "flex",
    "alignItems": "center",
    "gap": "0.35rem",
    "padding": "0.2rem 0.5rem",
    "fontSize": "13px",
    "fontFamily": "system-ui, sans-serif",
    "cursor": "pointer",
    "userSelect": "none"
};

def _status_letter(code: str) -> str {
    if code == "M" { return "M"; }
    if code == "A" { return "A"; }
    if code == "D" { return "D"; }
    if code == "R" { return "R"; }
    if code == "C" { return "C"; }
    return "U";
}

def _status_color(code: str) -> str {
    if code == "M" { return "#e2c08d"; }
    if code == "A" { return "#73c991"; }
    if code == "D" { return "#f48771"; }
    if code == "R" { return "#73c991"; }
    return "#73c991";
}

def:pub ScmFileRow(props: any) -> JsxElement {
    item = props["item"];
    staged = props["staged"];
    is_untracked = props["isUntracked"];
    on_open = props["onOpen"];
    on_stage = props["onStage"];
    on_unstage = props["onUnstage"];
    on_discard = props["onDiscard"];

    <div
        role="button"
        tabIndex={0}
        title={item["relPath"]}
        onClick={lambda (e: any) { on_open(item["path"], item["name"], staged); }}
        className="group"
        style={ROW_STYLE}
    >
        <span
            className={"codicon " + file_icon_class(item["name"], False, False)}
            style={{"fontSize": "14px", "opacity": "0.85", "flexShrink": "0"}}
        />
        <span style={{"flex": "1", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap", "color": "#CCCCCC"}}>
            {item["name"]}
        </span>
        <span
            className="opacity-0 group-hover:opacity-100 transition-opacity"
            style={{"display": "flex", "gap": "0.15rem", "flexShrink": "0"}}
        >
            {(
                <span
                    role="button"
                    title="Discard Changes"
                    aria-label={"Discard changes to " + item["name"]}
                    onClick={lambda (e: any) { e.stopPropagation(); on_discard(item["path"], is_untracked); }}
                    className="codicon codicon-discard"
                    style={{"fontSize": "14px", "opacity": "0.85"}}
                />
            ) if (not staged) else None}
            {(
                <span
                    role="button"
                    title="Stage Changes"
                    aria-label={"Stage " + item["name"]}
                    onClick={lambda (e: any) { e.stopPropagation(); on_stage(item["path"]); }}
                    className="codicon codicon-add"
                    style={{"fontSize": "14px", "opacity": "0.85"}}
                />
            ) if (not staged) else (
                <span
                    role="button"
                    title="Unstage Changes"
                    aria-label={"Unstage " + item["name"]}
                    onClick={lambda (e: any) { e.stopPropagation(); on_unstage(item["path"]); }}
                    className="codicon codicon-remove"
                    style={{"fontSize": "14px", "opacity": "0.85"}}
                />
            )}
        </span>
        <span
            aria-hidden="true"
            style={{"fontSize": "11px", "fontWeight": "600", "width": "14px", "textAlign": "center", "flexShrink": "0", "color": _status_color(item["status"])}}
        >
            {_status_letter(item["status"])}
        </span>
    </div>
}

def:pub app(active: bool, onOpenDiff: any, onNotify: any) -> JsxElement {
    has status: dict[str, any] = _EMPTY_STATUS;
    has commit_message: str = "";
    has committing: bool = False;

    async def refresh_status -> None;
    async def handle_stage(path: str) -> None;
    async def handle_unstage(path: str) -> None;
    async def handle_discard(path: str, is_untracked: bool) -> None;
    async def handle_stage_all -> None;
    async def handle_unstage_all -> None;
    def handle_message_change(e: any) -> None;
    async def handle_commit -> None;

    useEffect(lambda {
        if active {
            refresh_status();
        }
    }, [active]);

    has_staged = len(status["staged"]) > 0;

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%"}}>
        <div style={{"padding": "0.5rem", "borderBottom": "1px solid #2A2B2C", "display": "flex", "flexDirection": "column", "gap": "0.4rem"}}>
            <div style={{"display": "flex", "alignItems": "center", "gap": "0.4rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                <span className="codicon codicon-git-branch" style={{"fontSize": "13px"}} />
                <span style={{"flex": "1", "overflow": "hidden", "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>
                    {status["branch"] if status["is_repo"] else "No repository"}
                </span>
                <span
                    role="button"
                    title="Refresh"
                    aria-label="Refresh source control status"
                    onClick={lambda (e: any) { refresh_status(); }}
                    className="codicon codicon-refresh"
                    style={{"cursor": "pointer", "opacity": "0.85"}}
                />
            </div>
            {(
                <div style={{"display": "flex", "flexDirection": "column", "gap": "0.3rem"}}>
                    <Textarea
                        value={commit_message}
                        onChange={handle_message_change}
                        placeholder="Commit message"
                        aria-label="Commit message"
                        style={{"fontSize": "12px", "minHeight": "3.5rem", "resize": "vertical"}}
                    />
                    <Button
                        size="sm"
                        disabled={(not has_staged) or committing or (commit_message.strip() == "")}
                        onClick={lambda (e: any) { handle_commit(); }}
                    >
                        <span className="codicon codicon-check" style={{"fontSize": "13px", "marginRight": "0.3rem"}} />
                        Commit
                    </Button>
                </div>
            ) if status["is_repo"] else None}
        </div>
        <div style={{"flex": "1", "overflow": "auto"}}>
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    Open a folder that's a git repository to see source control status.
                </div>
            ) if not status["is_repo"] else None}
            {(
                <div>
                    <div style={{"display": "flex", "alignItems": "center", "gap": "0.3rem", "padding": "0.3rem 0.5rem", "fontSize": "11px", "fontWeight": "600", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                        <span style={{"flex": "1"}}>{"STAGED CHANGES (" + str(len(status["staged"])) + ")"}</span>
                        <span role="button" title="Unstage All" onClick={lambda (e: any) { handle_unstage_all(); }} className="codicon codicon-remove-all" style={{"cursor": "pointer", "opacity": "0.85"}} />
                    </div>
                    {[
                        <ScmFileRow
                            key={item["path"]}
                            item={item}
                            staged={True}
                            isUntracked={False}
                            onOpen={onOpenDiff}
                            onStage={handle_stage}
                            onUnstage={handle_unstage}
                            onDiscard={handle_discard}
                        />
                        for item in status["staged"]
                    ]}
                </div>
            ) if (status["is_repo"] and len(status["staged"]) > 0) else None}
            {(
                <div>
                    <div style={{"display": "flex", "alignItems": "center", "gap": "0.3rem", "padding": "0.3rem 0.5rem", "fontSize": "11px", "fontWeight": "600", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                        <span style={{"flex": "1"}}>{"CHANGES (" + str(len(status["unstaged"])) + ")"}</span>
                        <span role="button" title="Stage All" onClick={lambda (e: any) { handle_stage_all(); }} className="codicon codicon-add" style={{"cursor": "pointer", "opacity": "0.85"}} />
                    </div>
                    {[
                        <ScmFileRow
                            key={item["path"]}
                            item={item}
                            staged={False}
                            isUntracked={False}
                            onOpen={onOpenDiff}
                            onStage={handle_stage}
                            onUnstage={handle_unstage}
                            onDiscard={handle_discard}
                        />
                        for item in status["unstaged"]
                    ]}
                </div>
            ) if (status["is_repo"] and len(status["unstaged"]) > 0) else None}
            {(
                <div>
                    <div style={{"padding": "0.3rem 0.5rem", "fontSize": "11px", "fontWeight": "600", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                        {"UNTRACKED (" + str(len(status["untracked"])) + ")"}
                    </div>
                    {[
                        <ScmFileRow
                            key={item["path"]}
                            item={item}
                            staged={False}
                            isUntracked={True}
                            onOpen={onOpenDiff}
                            onStage={handle_stage}
                            onUnstage={handle_unstage}
                            onDiscard={handle_discard}
                        />
                        for item in status["untracked"]
                    ]}
                </div>
            ) if (status["is_repo"] and len(status["untracked"]) > 0) else None}
            {(
                <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                    No changes.
                </div>
            ) if (status["is_repo"] and len(status["staged"]) == 0 and len(status["unstaged"]) == 0 and len(status["untracked"]) == 0) else None}
        </div>
    </div>
}
