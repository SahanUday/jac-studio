"""DebugConsole: DAP client UI, a bottom-panel tab beside Terminal/Output/Problems.
Reuses `onOpenLocation` (shared with Problems/search) to reveal the stopped line.
SSE stream read via raw `fetch` (not the RPC stub); each frame needs two `JSON.parse` calls,
mirroring `terminal.impl.jac`. Continue/step/stop use `dap_client.jac`'s file-based command
channel (ADR 0049). Single panel (toolbar+status+stack+vars+output), not four views -- v1 scope."""

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
