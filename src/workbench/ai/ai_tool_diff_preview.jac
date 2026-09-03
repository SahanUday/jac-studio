"""AiToolDiffPreviewApp: the diff half of the multi-file-edit-review gap `docs/architecture.md`
flags right alongside tool approval -- `scm_diff_editor.jac`'s sibling for the "review a proposed
Claude Code Edit/Write before it lands on disk" case, not a reuse of that component or
`monaco_diff_editor.jac` directly.

**Content arrives pre-computed as props, not fetched on mount.** Unlike both existing diff
components (`monaco_diff_editor.jac` reads two real on-disk paths, `scm_diff_editor.jac` fetches a
git blob), `claude_code_launcher.py`'s `can_use_tool` callback already computed `originalText`/
`modifiedText` before the approval card was even shown (see that module's own docstring for how) --
there's nothing left for this component to fetch, and re-fetching `originalText` from disk here
would be actively wrong while the tool call is still pending approval (nothing has changed on disk
yet to fetch).

**Synthetic model URIs, marker-qualified by `toolUseId`, not just `filePath` -- one step beyond
`scm_diff_editor.jac`'s own `staged`-qualified marker, for a gap that pattern doesn't have.** A git
diff only ever has two variants of one file (staged/unstaged) open at once; this card can have
*multiple concurrent* pending approvals against the very same `filePath` (Claude asking for two
sequential edits to one file before either is decided), so `filePath` alone would let two live
cards' synthetic URIs collide and stomp each other's primed model content. Keying by the SDK's own
`tool_use_id` (already unique per call, see `claude_code_launcher.py`'s docstring) instead avoids
that, and -- the same reasoning `scm_diff_editor.jac` gives for its own synthetic URIs -- guards
against ever colliding with `filePath`'s *real* URI if that file also happens to be open in a
regular editor tab right now.

Read-only, both sides -- this is a review-before-it-happens surface, not an editable one.

**`renderSideBySide: False`** (inline/unified diff, not the two-pane view `monaco_diff_editor.jac`/
`scm_diff_editor.jac` both use) -- both of those live in a full editor group with real width to
spare; this card lives inside `ai_chat.jac`'s narrow sidebar panel (that module's own docstring
already names the narrow width as a deliberate v1 tradeoff), where two side-by-side panes would
each be too cramped to read."""

import from "@monaco-editor/react" { DiffEditor }
import from src.editor.client.jac_language { register_jac_language }

def _synthetic_uri(marker: str, tool_use_id: str, file_path: str) -> str {
    return "/.jac-studio-ai-diff-" + marker + "-" + tool_use_id + file_path;
}

def:pub app(toolUseId: str, filePath: str, originalText: str, modifiedText: str) -> JsxElement {
    def handle_before_mount(monaco: any) {
        register_jac_language(monaco);
        original_uri = monaco.Uri.parse(_synthetic_uri("original", toolUseId, filePath));
        if not monaco.editor.getModel(original_uri) {
            monaco.editor.createModel(originalText, "", original_uri);
        }
        modified_uri = monaco.Uri.parse(_synthetic_uri("modified", toolUseId, filePath));
        if not monaco.editor.getModel(modified_uri) {
            monaco.editor.createModel(modifiedText, "", modified_uri);
        }
    }

    <DiffEditor
        height="220px"
        original={originalText}
        modified={modifiedText}
        originalModelPath={_synthetic_uri("original", toolUseId, filePath)}
        modifiedModelPath={_synthetic_uri("modified", toolUseId, filePath)}
        theme="vs-dark"
        beforeMount={handle_before_mount}
        keepCurrentOriginalModel={True}
        keepCurrentModifiedModel={True}
        options={{"readOnly": True, "automaticLayout": True, "renderSideBySide": False}}
    />
}
