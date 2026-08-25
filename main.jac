"""jac-studio -- entry point. Mounts `src/workbench/shell/workbench.jac`'s `Workbench`, which
composes the two Phase 2 workbench-shell pieces built so far -- the lazy file-tree sidebar
(`src/workbench/file_tree/file_tree.jac`) and the tab bar / editor content area
(`src/workbench/editor_tabs/editor_tabs.jac`, wrapping Phase 1's `text_editor.jac`) -- and owns the
"which files are open" state connecting them. Selecting a file in the tree now opens (or
activates) a real tab backed by `src/editor/document_service.jac`'s per-path buffer cache.

**Global stylesheet (2026-08-25)** -- `import ".styles.global.css";` below was missing since this
project's inception: every Phase 1/2 PR verified via `jac check`/`jac test`/compiled-bundle
inspection and RPC probes, never an actual rendered browser, so a real Tailwind/shadcn CSS bundle
never once shipped despite every component consistently authoring `className`s and inline styles
against it -- caught only once real browser screenshots (`jac browse`) were taken. Must be the
first import (matches the `jac-shadcn` template's own `main.jac`), though it can't be the literal
first *statement* in a file that also has a module docstring -- Jac only allows a bare string
statement in the true first-statement position.
"""

import ".styles.global.css";
import from src.workbench.shell.workbench { app as WorkbenchApp }

# `run_in_terminal` (src/workbench/terminal/terminal_service.jac) is consumed by a raw SSE `fetch`
# in terminal.jac, not a generated RPC stub -- with no client-side reference to trigger manifest
# self-registration, this top-level import is what registers the /function/run_in_terminal route at
# all (see the jac-sv-streaming guide's "Registration: streams need an entry-module import" section).
import from src.workbench.terminal.terminal_service { run_in_terminal }

def:pub app -> JsxElement {
    <WorkbenchApp />
}
