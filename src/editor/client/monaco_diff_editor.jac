"""MonacoDiffEditorApp: Phase 3's diff-editor mode (`docs/roadmap.md`) -- wraps
`@monaco-editor/react`'s `DiffEditor`, the sibling of the plain `Editor` `monaco_editor.jac` already
wraps, following the same thin-JSX-wrapper shape.

**Confirms `docs/architecture.md`'s open question empirically, rather than assuming it** ("confirm
whether/how the same shared-model semantics apply before assuming the diff editor composes ... for
free"): verified live (`jac browse`) that `originalModelPath`/`modifiedModelPath` give free
language detection from each side's file extension, the same as the plain editor's own `path` prop
-- and that a `keepCurrentModel`-shaped fix is needed here for the identical reason
`monaco_editor.jac` needs one: diffing a file that's *also* open in a regular tab reuses that
file's existing shared Monaco model (`monaco.editor.getModel(uri) || createModel(...)`), so closing
the diff tab without it disposes the model the regular tab is still rendering.

**`DiffEditor` has no `keepCurrentModel` prop at all -- caught live, not by reading the docs.**
Passing `keepCurrentModel={True}` (the plain `Editor`'s prop name) compiles and runs with zero
warning, but `@monaco-editor/react`'s `DiffEditor` silently ignores it: reading the package's own
source (`node_modules/@monaco-editor/react/dist/index.js`) shows its unmount cleanup as
`keepCurrentOriginalModel || original.dispose(); keepCurrentModifiedModel || modified.dispose();`
-- two separate, differently-named props, both defaulting to `False`. Confirmed by reproducing the
exact failure first: open a file as a regular tab, diff it against another file, close the diff tab
-- the regular tab went blank with `Uncaught Error: TextModel got disposed before
DiffEditorWidget model got reset` in the console, `jac check`/`jac test` both silent on it (a pure
runtime/prop-name defect, the same class of gap as `monaco_editor.jac`'s own `keepCurrentModel`
finding, just one level more specific to this component). Setting both
`keepCurrentOriginalModel`/`keepCurrentModifiedModel` fixed it, verified against the same repro.

**Read-only, both sides.** A compare-two-files view, not a merge-conflict resolution surface --
that's explicitly a later, git-paired Phase 4 feature (`docs/roadmap.md`) once there's a real merge
to resolve. `options={{"readOnly": True}}` covers both panes; nothing here needs
upstream's separate `originalEditable` toggle.

**Triggered from `file_tree.jac`'s Alt+Click "select for compare" gesture**, not a context menu --
see that module's docstring for why the file-tree right-click menu isn't a prerequisite here.

Load/read-only by the document boundary, same as `monaco_editor.jac`: both sides are read once via
`document_service.open_document` on mount; nothing here writes back, so there's no save path to
wire (matching the read-only intent above).
"""

import from "@monaco-editor/react" { DiffEditor }
import from src.editor.document_service { open_document }

def:pub app(originalPath: str, modifiedPath: str) -> JsxElement {
    has original_content: str = "";
    has modified_content: str = "";
    has loaded: bool = False;

    async can with entry {
        original_result = await open_document(originalPath);
        modified_result = await open_document(modifiedPath);
        original_content = original_result["content"];
        modified_content = modified_result["content"];
        loaded = True;
    }

    <div style={{"height": "100%", "width": "100%"}}>
        {(
            <DiffEditor
                original={original_content}
                modified={modified_content}
                originalModelPath={originalPath}
                modifiedModelPath={modifiedPath}
                theme="vs-dark"
                keepCurrentOriginalModel={True}
                keepCurrentModifiedModel={True}
                options={{"readOnly": True, "automaticLayout": True}}
            />
        ) if loaded else (
            <div style={{"padding": "1rem", "fontSize": "12px", "color": "#888", "fontFamily": "system-ui, sans-serif"}}>
                Loading diff...
            </div>
        )}
    </div>
}
