"""jac-studio -- entry point. Combines the document service (server) with the minimal editor
client component (Phase 1's roadmap deliverable) -- see src/editor/document_service.jac and
src/editor/client/text_editor.jac.
"""

import from src.editor.document_service { get_document_lines, apply_document_edit }

import from src.editor.client.text_editor { app as TextEditorApp }

def:pub app -> JsxElement {
    <TextEditorApp />
}
