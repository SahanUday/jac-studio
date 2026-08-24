"""jac-studio -- entry point. Combines the document service (server) with the minimal editor
client component (Phase 1's roadmap deliverable) -- see src/editor/document_service.jac and
src/editor/client/text_editor.jac -- alongside Phase 2's first workbench-shell piece, the lazy
file-tree sidebar (`src/workbench/file_tree/file_tree.jac`).

The two are shown side by side purely as a visual placement, not wired together yet: selecting a
file in the tree doesn't load its content into the editor -- that's Tabs/editor-group work, a
separate roadmap bullet.
"""

import from src.editor.document_service { get_document_lines, apply_document_edit }

import from src.editor.client.text_editor { app as TextEditorApp }
import from src.workbench.file_tree.file_tree { app as FileTreeApp }

def:pub app -> JsxElement {
    <div style={{"display": "flex", "height": "100vh"}}>
        <div style={{"width": "260px", "flexShrink": "0", "borderRight": "1px solid #3c3c3c", "overflow": "hidden"}}>
            <FileTreeApp />
        </div>
        <div style={{"flex": "1", "overflow": "auto"}}>
            <TextEditorApp />
        </div>
    </div>
}
