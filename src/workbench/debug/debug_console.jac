"""DebugConsole: the UI half of Phase 4's DAP client bullet (`docs/roadmap.md`) -- "a debug session
can set a breakpoint and step through at least one language's code via a real DAP adapter." A
fourth bottom-panel tab, next to Terminal/Output/Problems, following the exact `_toggle_panel`/
`active_bottom_panel` mechanism `workbench.jac`'s own docstring already generalized for a
one-branch addition (Problems was the proof; this is the next one).

**`onOpenLocation` is reused, not a new "jump to the current line" mechanism.** Every `stopped`
event calls the same `open_search_result(path, name, line, column)` handler `problems.jac`/
`search.jac`/go-to-definition already reuse -- it already does exactly what a debugger's "reveal
current line" needs (open-or-activate the right tab, seed the cursor at the stopped line), so a
debug session literally watching itself step through code falls out of infrastructure that already
exists, rather than a new decoration-overlay mechanism in `monaco_editor.jac`.

**The SSE stream is consumed with a raw `fetch`, not the generated RPC stub -- same reasoning as
`terminal.jac`'s own `run_in_terminal` consumption.** `dap_client.jac`'s `start_debug_session` is
declared `-> Generator` specifically so it stays a real server-push stream; an RPC stub can't
consume one. Each yielded line is `json.dumps(event)` (a JSON *string*) rather than a plain text
line the way `run_in_terminal` yields -- jaclang's own SSE dispatcher already JSON-encodes whatever
string a `Generator[str]` yields as the wire payload, so `handle_start`'s parsing does two
`JSON.parse` calls per frame: one to undo the dispatcher's own string-encoding (matching
`terminal.impl.jac`'s `chunk = JSON.parse(line[6:])` exactly), a second to decode the JSON *this*
module's own payload actually carries.

**`and not frame.startswith("event:")` (2026-09-01 fix) -- a real, 100%-reproducible bug found live,
not theoretical.** jaclang's own SSE dispatcher emits a trailing `event: end\ndata: {}` frame after
the generator returns, on *every* session end (manual stop or natural completion) -- confirmed
directly, both via a raw `curl -N` capture of the stream and via the browser console. The initial
version of this loop copied `terminal.impl.jac`'s `chunk = JSON.parse(line[6:])` line but dropped
its `and not frame.startswith("event:")` guard, so that trailing frame's bare `data: {}` (a JSON
*object* literal, not this module's expected JSON *string* payload) fed into the same two-`JSON.parse`
call: the first parse succeeds (`{}` is valid JSON), but the *second* parse receives an actual JS
object where a string was expected, coercing it to the literal text `"[object Object]"` and throwing
`SyntaxError: "[object Object]" is not valid JSON` -- confirmed via the exact browser-console
traceback. Since this throw was never caught, it aborted `handle_start`'s `async def` entirely,
skipping the loop's own post-loop cleanup (`session_active = False; ...`) -- the reason a session
that ended *without* the user clicking Stop left the Start button permanently disabled afterward
(`session_active` stuck `True` forever), matching the "debugging stops working after the first
run" bug reported live. Restoring the same guard `terminal.impl.jac` already has fixes it at the
source, for every termination path, not just the manual-stop one `handle_stop`'s own direct
`session_active = False` happened to paper over.

**`handle_start` fetches `get_breakpoints(path)` itself and sends the result as `start_debug_session`'s
`lines` argument, rather than trusting the server to already know them.** `dap_client.jac`'s own
docstring explains why: a `Generator`-returning SSE function runs in a genuinely separate process
from the plain RPC call that stored those breakpoints, so `start_debug_session` has no way to look
them up itself -- the client has to hand them over explicitly.

**Continue/step/stop calls are ordinary RPC stubs, not part of the stream.** They reach the live
session via `dap_client.jac`'s file-based command channel (see that module's own docstring for why
a `glob` cache can't do this instead), concurrently with the still-open SSE stream -- the same
"other calls can still reach the server while a stream is open" pattern this project's other
server-push features already rely on.

**A single toolbar+status+call-stack+variables+output panel, not four separate views.** Real VS
Code splits this across a Debug sidebar (call stack, variables, watch, breakpoints) plus a bottom
Debug Console panel (output). A v1 scope cut deliberate here: this project's own bottom-panel area
already hosts everything else Phase 4 shipped (Terminal/Output/Problems), and one panel showing
toolbar + status + call stack + variables + output together is enough to actually set a breakpoint
and step through code, the stated exit criterion -- splitting call stack/variables into their own
sidebar views is real follow-up work, not something this bullet's exit criterion requires."""

import from "react" { useState }
import from src.workbench.dap.dap_client { continue_execution, step_over, step_into, step_out, stop_session, get_breakpoints }

def:pub app(active: bool, path: str, onOpenLocation: any) -> JsxElement {
    has session_active: bool = False;
    has status: str = "idle";
    has status_message: str = "";
    has frames: list[dict[str, any]] = [];
    has variables: list[dict[str, any]] = [];
    has output_lines: list[str] = [];

    async def handle_start -> None;
    def handle_event(event: dict[str, any]) -> None;
    async def handle_continue -> None;
    async def handle_step_over -> None;
    async def handle_step_into -> None;
    async def handle_step_out -> None;
    async def handle_stop -> None;

    can_debug = path.endswith(".jac");
    stopped = status == "stopped";

    <div style={{"height": "100%", "display": "flex", "flexDirection": "column", "fontFamily": "system-ui, sans-serif", "fontSize": "12px", "color": "#CCCCCC"}}>
        <div style={{"display": "flex", "alignItems": "center", "gap": "0.4rem", "padding": "0.4rem 0.6rem", "borderBottom": "1px solid #2A2B2C", "flexShrink": "0"}}>
            <button
                onClick={handle_start}
                disabled={session_active or not can_debug}
                title="Start Debugging"
                style={{"background": "transparent", "border": "none", "color": "#8C8C8C" if (session_active or not can_debug) else "#CCCCCC", "cursor": "pointer" if not (session_active or not can_debug) else "default", "padding": "0.15rem"}}
            >
                <span className="codicon codicon-debug-start" style={{"fontSize": "16px"}} />
            </button>
            <button
                onClick={handle_continue}
                disabled={not stopped}
                title="Continue"
                style={{"background": "transparent", "border": "none", "color": "#CCCCCC" if stopped else "#5A5A5A", "cursor": "pointer" if stopped else "default", "padding": "0.15rem"}}
            >
                <span className="codicon codicon-debug-continue" style={{"fontSize": "16px"}} />
            </button>
            <button
                onClick={handle_step_over}
                disabled={not stopped}
                title="Step Over"
                style={{"background": "transparent", "border": "none", "color": "#CCCCCC" if stopped else "#5A5A5A", "cursor": "pointer" if stopped else "default", "padding": "0.15rem"}}
            >
                <span className="codicon codicon-debug-step-over" style={{"fontSize": "16px"}} />
            </button>
            <button
                onClick={handle_step_into}
                disabled={not stopped}
                title="Step Into"
                style={{"background": "transparent", "border": "none", "color": "#CCCCCC" if stopped else "#5A5A5A", "cursor": "pointer" if stopped else "default", "padding": "0.15rem"}}
            >
                <span className="codicon codicon-debug-step-into" style={{"fontSize": "16px"}} />
            </button>
            <button
                onClick={handle_step_out}
                disabled={not stopped}
                title="Step Out"
                style={{"background": "transparent", "border": "none", "color": "#CCCCCC" if stopped else "#5A5A5A", "cursor": "pointer" if stopped else "default", "padding": "0.15rem"}}
            >
                <span className="codicon codicon-debug-step-out" style={{"fontSize": "16px"}} />
            </button>
            <button
                onClick={handle_stop}
                disabled={not session_active}
                title="Stop"
                style={{"background": "transparent", "border": "none", "color": "#CCCCCC" if session_active else "#5A5A5A", "cursor": "pointer" if session_active else "default", "padding": "0.15rem"}}
            >
                <span className="codicon codicon-debug-stop" style={{"fontSize": "16px"}} />
            </button>
            <span style={{"marginLeft": "0.5rem", "color": "#f48771" if status == "error" else "#8C8C8C"}}>
                {status_message if status_message != "" else ("Open a .jac file to debug it" if not can_debug else "Not running")}
            </span>
        </div>
        <div style={{"flex": "1", "overflow": "hidden", "display": "flex"}}>
            <div style={{"width": "50%", "overflow": "auto", "borderRight": "1px solid #2A2B2C"}}>
                <div style={{"padding": "0.3rem 0.6rem", "color": "#8C8C8C", "fontSize": "11px", "textTransform": "uppercase"}}>Call Stack</div>
                {[
                    <div key={str(f["id"]) + ":" + f["name"]} style={{"padding": "0.15rem 0.6rem", "whiteSpace": "nowrap"}}>
                        {f["name"] + "  " + f["path"].split("/")[-1] + ":" + str(f["line"])}
                    </div>
                    for f in frames
                ]}
                <div style={{"padding": "0.3rem 0.6rem", "color": "#8C8C8C", "fontSize": "11px", "textTransform": "uppercase", "marginTop": "0.5rem"}}>Variables</div>
                {[
                    <div key={v["name"]} style={{"padding": "0.15rem 0.6rem", "whiteSpace": "nowrap"}}>
                        <span style={{"color": "#9CDCFE"}}>{v["name"]}</span>
                        <span style={{"color": "#8C8C8C"}}>{": "}</span>
                        <span>{v["value"]}</span>
                    </div>
                    for v in variables
                ]}
            </div>
            <div style={{"width": "50%", "overflow": "auto", "padding": "0.3rem 0.6rem", "whiteSpace": "pre-wrap", "fontFamily": "monospace"}}>
                {[<div key={str(i)}>{line}</div> for (i, line) in enumerate(output_lines)]}
            </div>
        </div>
    </div>
}
