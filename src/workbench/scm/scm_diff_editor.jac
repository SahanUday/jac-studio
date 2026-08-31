"""ScmDiffEditorApp: the diff view a click on an `Scm` sidebar row opens -- `monaco_diff_editor.jac`'s
sibling for the git-diff case, not a reuse of that component directly.

**Fetches content itself from `filePath`/`staged`, not passed pre-fetched paths** -- unlike
`monaco_diff_editor.jac`'s two real on-disk `originalPath`/`modifiedPath` (each independently
loadable via `document_service.open_document`), a git diff's "original" side is a `HEAD` blob with
no real filesystem path to give `open_document` at all. `workbench.impl.jac`'s `open_scm_diff`
therefore stores only `{filePath, staged}` in the tab dict (small, session-persistence-friendly,
matching every other tab shape) and this component re-fetches `git_service.get_diff_content` itself
on mount, the same "leaf fetches its own data" shape `monaco_diff_editor.jac` already uses for its
own `can with entry` -- re-fetching on every mount (not cached) is deliberate: the whole point of
reopening this diff is to see the *current* state of a possibly-still-changing file, not a stale
snapshot from whenever the tab was first opened.

**Synthetic model URIs, never the file's own real path** -- `monaco.editor.getModel(uri) || ...`
model sharing is exactly right for `monaco_diff_editor.jac`'s two-real-files case (two tabs
comparing the same file should share one model), but is actively wrong here: if `filePath` is also
open as a regular editor tab, reusing its real URI for either side would silently hand this
read-only diff the *live, currently-being-edited* buffer instead of the actual git blob content
just fetched, and -- far worse -- would let this component's own model-priming logic stomp on the
regular tab's live model with stale diff content. Both sides get a distinct, never-colliding
synthetic URI (a fixed marker segment prepended to the real path, `staged`-qualified so the staged
and unstaged diffs of the same file don't collide with each other either) with the real extension
preserved at the end for Monaco's own language auto-detection to still work.

Read-only, both sides, same as `monaco_diff_editor.jac` -- this is a change-review surface, not
`docs/roadmap.md`'s separate, not-yet-built merge-conflict resolution UI."""

import from "@monaco-editor/react" { DiffEditor }
import from src.workbench.scm.git_service { get_diff_content }
import from src.editor.client.jac_language { register_jac_language }

def _synthetic_uri(marker: str, file_path: str, staged: bool) -> str {
    suffix = "-staged" if staged else "-unstaged";
    return "/.jac-studio-scm-" + marker + suffix + file_path;
}

def:pub app(filePath: str, staged: bool) -> JsxElement {
    has original_content: str = "";
    has modified_content: str = "";
    has loaded: bool = False;

    async can with entry {
        result = await get_diff_content(filePath, staged);
        original_content = result["original"];
        modified_content = result["modified"];
        loaded = True;
    }

    def handle_before_mount(monaco: any) {
        register_jac_language(monaco);
        original_uri = monaco.Uri.parse(_synthetic_uri("original", filePath, staged));
        if not monaco.editor.getModel(original_uri) {
            monaco.editor.createModel(original_content, "", original_uri);
        }
        modified_uri = monaco.Uri.parse(_synthetic_uri("modified", filePath, staged));
        if not monaco.editor.getModel(modified_uri) {
            monaco.editor.createModel(modified_content, "", modified_uri);
        }
    }

    <div style={{"height": "100%", "width": "100%"}}>
        {(
            <DiffEditor
                original={original_content}
                modified={modified_content}
                originalModelPath={_synthetic_uri("original", filePath, staged)}
                modifiedModelPath={_synthetic_uri("modified", filePath, staged)}
                theme="vs-dark"
                beforeMount={handle_before_mount}
                keepCurrentOriginalModel={True}
                keepCurrentModifiedModel={True}
                options={{"readOnly": True, "automaticLayout": True}}
            />
        ) if loaded else (
            <div style={{"padding": "1rem", "fontSize": "12px", "color": "#8C8C8C", "fontFamily": "system-ui, sans-serif"}}>
                Loading diff...
            </div>
        )}
    </div>
}
