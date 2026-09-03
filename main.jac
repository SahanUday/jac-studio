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

# Same reason, same fix: `start_debug_session` (src/workbench/dap/dap_client.jac) is also consumed
# by a raw SSE `fetch` (in debug_console.impl.jac), not a generated RPC stub -- needs the identical
# entry-module import to register /function/start_debug_session at all.
import from src.workbench.dap.dap_client { start_debug_session }
import from src.workbench.settings.settings_service { get_setting, set_setting }

# Same reason, same fix as the two imports above: `start_chat_turn`
# (src/workbench/ai/claude_code_client.jac) is also consumed by a raw SSE `fetch` (in
# ai_chat.impl.jac), not a generated RPC stub -- needs the identical entry-module import to
# register /function/start_chat_turn at all.
import from src.workbench.ai.claude_code_client { start_chat_turn }

"""**Dark mode was never activated (2026-08-25, caught via real browser screenshots, again not
compiled-bundle inspection)** -- `styles/global.css` defines dark-theme values behind
`@custom-variant dark (&:is(.dark *));`, a *class-based* switch: every shadcn component (`Sidebar`,
`Dialog`, `Command`, `Button`) only picks up its dark palette for descendants of a `.dark`-classed
ancestor, and nothing in this codebase ever added that class anywhere. `workbench.jac`'s own
hand-styled pieces (tab bar, terminal, status bar) use hardcoded dark hex colors via inline
`style={{}}`, so they always looked dark regardless -- but every shadcn-driven surface (the file
tree's `Sidebar`, the command palette's `Dialog`, buttons) was rendering in shadcn's *light* theme
this whole time, which is why the app looked like a light-and-dark patchwork instead of a
consistent VS-Code-style dark UI. `dark` is applied here, once, at the true root -- everything
`WorkbenchApp` renders is a descendant, so this is the one place that needs it."""
def:pub app -> JsxElement {
    has theme: str = "dark";

    async can with entry {
        theme = await get_setting("workbench.colorTheme", "dark");
    }

    async def toggle_theme -> None;

    <div className={theme}>
        <WorkbenchApp onToggleTheme={toggle_theme} />
    </div>
}
