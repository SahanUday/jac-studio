"""jac-studio entry point. Mounts the workbench shell and applies the theme class at the true root.

`.styles.global.css` must be the first import, but cannot be the first *statement* in a file that
also has a module docstring."""

import ".styles.global.css";
import from src.workbench.shell.workbench { app as WorkbenchApp }

# These four are consumed by raw SSE `fetch` calls, not generated RPC stubs. With no client-side
# reference to trigger manifest self-registration, these top-level imports are the only thing that
# registers their /function/... routes. See jac-sv-streaming, "streams need an entry-module import".
import from src.workbench.terminal.terminal_service { attach_session }
import from src.workbench.dap.dap_client { start_debug_session }
import from src.workbench.settings.settings_service { get_setting, set_setting }
import from src.workbench.ai.claude_code_client { start_chat_turn }

"""The theme class must be applied here, at the true root, which also paints `background`/`color`
from theme CSS vars directly so no descendant gap can fall through to the page's own default
background. See ADR 0068."""
def:pub app -> JsxElement {
    has theme: str = "dark";

    async can with entry {
        theme = await get_setting("workbench.colorTheme", "dark");
    }

    async def toggle_theme -> None;

    <div className={theme} style={{"background": "var(--background)", "color": "var(--foreground)", "height": "100vh"}}>
        <WorkbenchApp onToggleTheme={toggle_theme} />
    </div>
}
