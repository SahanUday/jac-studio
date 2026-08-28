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

**No per-pane minimap, and that's not fixable from here.** Passing `minimap: {enabled: true}` in
`options` has zero effect on either pane -- read `monaco-editor`'s own source
(`diffEditor/components/diffEditorEditors.js`'s `_adjustOptionsForSubEditor`) to confirm why:
`clonedOptions.minimap.enabled = false;` is hardcoded, unconditionally, for both the original and
modified sub-editors, regardless of what the `DiffEditor` component's own `options` prop requests.
This is deliberate upstream design, not a `@monaco-editor/react` gap the way the model-language and
`keepCurrentModel` findings above are -- real VS Code's diff view has no per-pane minimap either;
whatever overview it shows comes from a separate mechanism entirely. Left un-set here rather than
passed and silently ignored.

**Triggered from `file_tree.jac`'s Alt+Click "select for compare" gesture**, not a context menu --
see that module's docstring for why the file-tree right-click menu isn't a prerequisite here.

Load/read-only by the document boundary, same as `monaco_editor.jac`: both sides are read once via
`document_service.open_document` on mount; nothing here writes back, so there's no save path to
wire (matching the read-only intent above).

**CORRECTION (2026-08-28, Phase 3's syntax-highlighting-confirmation bullet)**: the free
per-side language detection claimed above is only half true, found while separately verifying
Monaco's bundled tokenizers for that bullet. `getModels()` showed the diff's *original* side
correctly tagged (e.g. `jac`, once `jac_language.jac` registers it) but its *modified* side stuck
on `plaintext` -- reading `@monaco-editor/react`'s own model-resolution code
(`function b(e,t,r,o){return We(e,o)||_e(e,t,r,o)}`) explains why: the *original* side had already
been opened as a regular tab elsewhere in the same session, so `We` (`getModel(uri)`) found that
already-correctly-tagged model and reused it -- but the *modified* side had no other open tab, so
it fell into `_e()`, which creates a fresh model with the language argument `s||r||"text"`
(`modifiedLanguage||language||"text"`) -- a **literal fallback string `"text"`**, not the empty
string the plain `Editor` component uses in the same situation (its own fallback is `t||s||""`,
where `""` triggers Monaco's own auto-detection from the URI extension). `DiffEditor` never
auto-detects a side's language from `originalModelPath`/`modifiedModelPath` on its own -- it only
looks correct when the diffed file happens to already have a model from being open elsewhere.
Reproduced cold (fresh page load, diffing two files neither open as a regular tab): both sides
came back `plaintext` before the fix below.

**Fix**: `handle_before_mount` now pre-creates each side's model itself, in `beforeMount` (runs
synchronously before `DiffEditor`'s own model resolution, confirmed from the same source read) --
`monaco.editor.createModel(content, "", uri)`, the same empty-string-language spelling the plain
`Editor` path already relies on for auto-detection. `DiffEditor`'s internal `getModel(uri) || ...`
then finds this pre-created, correctly-tagged model instead of ever reaching its own
literal-`"text"` fallback. Verified against the same repro: a cold diff of two never-opened `.jac`
files now shows real Jac tokenization on both sides.
"""

import from "@monaco-editor/react" { DiffEditor }
import from src.editor.document_service { open_document }
import from src.editor.client.jac_language { register_jac_language }

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

    def handle_before_mount(monaco: any) {
        register_jac_language(monaco);
        original_uri = monaco.Uri.parse(originalPath);
        if not monaco.editor.getModel(original_uri) {
            monaco.editor.createModel(original_content, "", original_uri);
        }
        modified_uri = monaco.Uri.parse(modifiedPath);
        if not monaco.editor.getModel(modified_uri) {
            monaco.editor.createModel(modified_content, "", modified_uri);
        }
    }

    <div style={{"height": "100%", "width": "100%"}}>
        {(
            <DiffEditor
                original={original_content}
                modified={modified_content}
                originalModelPath={originalPath}
                modifiedModelPath={modifiedPath}
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
