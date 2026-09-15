"""MonacoDiffEditorApp: read-only two-file compare via `@monaco-editor/react`'s `DiffEditor`,
reached from `file_tree.jac`'s Alt+Click "select for compare".
`keepCurrentOriginalModel`/`keepCurrentModifiedModel` and the `beforeMount` model pre-creation are
both load-bearing and both fail silently if dropped -- see `docs/libraries/monaco.md`."""

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
