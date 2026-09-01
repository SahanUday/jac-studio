"""Consumes `start_debug_session`'s raw SSE stream (`app`'s own docstring explains why this isn't
an RPC stub, and the two-`JSON.parse` framing) and drives every state update from the events it
yields. Mirrors `terminal.impl.jac`'s exact `fetch` + `ReadableStream` reading loop."""
impl app.handle_start -> None {
    if session_active {
        return;
    }
    session_active = True;
    status = "running";
    status_message = "Starting...";
    frames = [];
    variables = [];
    output_lines = [];

    lines = await get_breakpoints(path);
    resp = await fetch("/function/start_debug_session", {
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "body": JSON.stringify({"path": path, "lines": lines})
    });
    reader = resp.body.getReader();
    decoder = new(TextDecoder);
    nl = chr(10);
    buf = "";
    feeding = True;
    while feeding {
        part = await reader.read();
        if part.done {
            feeding = False;
            continue;
        }
        buf = buf + decoder.decode(part.value, {"stream": True});
        raw_frames = buf.split(nl + nl);
        buf = raw_frames.pop();
        for frame in raw_frames {
            for line in frame.split(nl) {
                if line.startswith("data: ") {
                    chunk = JSON.parse(line[6:]) as str;
                    event = JSON.parse(chunk) as dict[str, any];
                    handle_event(event);
                }
            }
        }
    }
    session_active = False;
    if status == "running" {
        status = "terminated";
        status_message = "Session ended.";
    }
}

impl app.handle_event(event: dict[str, any]) -> None {
    event_type = event.get("type", "");
    if event_type == "started" {
        status = "running";
        status_message = "Running " + path.split("/")[-1];
        return;
    }
    if event_type == "output" {
        output_lines = output_lines + [event.get("text", "")];
        return;
    }
    if event_type == "stopped" {
        status = "stopped";
        status_message = "Stopped (" + str(event.get("reason", "")) + ") at line " + str(event.get("line", 0));
        frames = event.get("frames", []);
        variables = event.get("variables", []);
        stop_path = event.get("path", "");
        stop_line = event.get("line", 0);
        if onOpenLocation and stop_path != "" {
            onOpenLocation(stop_path, stop_path.split("/")[-1], stop_line, 1);
        }
        return;
    }
    if event_type == "continued" {
        status = "running";
        status_message = "Running...";
        frames = [];
        variables = [];
        return;
    }
    if event_type == "terminated" {
        status = "terminated";
        status_message = "Session ended.";
        frames = [];
        variables = [];
        return;
    }
    if event_type == "error" {
        status = "error";
        status_message = str(event.get("message", ""));
        return;
    }
}

impl app.handle_continue -> None {
    await continue_execution();
}

impl app.handle_step_over -> None {
    await step_over();
}

impl app.handle_step_into -> None {
    await step_into();
}

impl app.handle_step_out -> None {
    await step_out();
}

impl app.handle_stop -> None {
    await stop_session();
    session_active = False;
    status = "idle";
    status_message = "";
    frames = [];
    variables = [];
}
