"""Standalone entry point for the archived native editor -- lets this subtree be checked/tested
in isolation (`capped -- jac check internal/native-editor-archive`,
`capped -- jac test internal/native-editor-archive`) without needing it wired into the live
jac-studio app. Mirrors what the live `main.jac` looked like before the 2026-08-25 Monaco switch --
see this directory's README.md.
"""

import from src.editor.client.text_editor { app as TextEditorApp }

def:pub app -> JsxElement {
    <TextEditorApp path="/tmp/native-editor-archive-demo.txt" />
}
