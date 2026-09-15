"""Git-diff view opened from an `Scm` sidebar row; `monaco_diff_editor.jac`'s sibling for blobs with
no real filesystem path (`HEAD` content), fetching `get_diff_content` itself on every mount.
Uses synthetic model URIs (never the file's real path) with the real extension preserved, so
language auto-detection works without colliding with a real open tab's live model. Read-only.
Reloads on a clean external change by refetching (ADR 0072) -- correct here since `<DiffEditor>`
is controlled, unlike `monaco_editor.jac`'s uncontrolled `defaultValue`."""

import from "react" { useEffect }
import from "@monaco-editor/react" { DiffEditor }
import from src.workbench.scm.git_service { get_diff_content }
import from src.editor.client.jac_language { register_jac_language }

def _synthetic_uri(marker: str, file_path: str, staged: bool) -> str {
    suffix = "-staged" if staged else "-unstaged";
    return "/.jac-studio-scm-" + marker + suffix + file_path;
}

def:pub app(filePath: str, staged: bool, reloadNonce: any) -> JsxElement {
    has original_content: str = "";
    has modified_content: str = "";
    has loaded: bool = False;

    async can with entry {
        result = await get_diff_content(filePath, staged);
        original_content = result["original"];
        modified_content = result["modified"];
        loaded = True;
    }

    async def refresh_diff -> None {
        result = await get_diff_content(filePath, staged);
        original_content = result["original"];
        modified_content = result["modified"];
    }

    # reloadNonce == 0 means "nothing pending" (workbench.jac's default for a path with no entry in
    # filesPendingReload); also skips the mount-time firing every useEffect gets for free, since
    # content is already freshly loaded by can with entry above at that point.
    useEffect(lambda {
        if reloadNonce == 0 or not loaded {
            return;
        }
        refresh_diff();
    }, [reloadNonce]);

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
