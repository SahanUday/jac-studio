"""Read-only diff preview for a pending Claude Code Edit/Write, rendered with its approval card.
Text arrives pre-computed as props -- re-fetching `originalText` from disk would be wrong while the
call is still pending. Model URIs are synthetic and keyed by `toolUseId`, not `filePath`, because
concurrent approvals can target the same file. Unified rather than side-by-side: this renders in
`ai_chat.jac`'s narrow sidebar."""

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
