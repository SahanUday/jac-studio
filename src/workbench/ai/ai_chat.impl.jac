"""Consumes `start_chat_turn`'s raw SSE stream (`app`'s own docstring explains why this isn't an
RPC stub) and drives every state update from the events it yields. Mirrors
`debug_console.impl.jac`'s exact `fetch` + `ReadableStream` reading loop, including the
two-`JSON.parse` unwrap and the `and not frame.startswith("event:")` guard against the trailing
`event: end` frame jaclang's own SSE dispatcher always sends -- see that module's own docstring for
the live-reproduced bug this guard exists to prevent."""
impl app.handle_send -> None {
    if not (input_text.strip() != "" and not is_streaming) {
        return;
    }
    prompt = input_text;
    input_text = "";
    messages = messages + [{"role": "user", "text": prompt}, {"role": "assistant", "text": ""}];
    is_streaming = True;

    resp = await fetch("/function/start_chat_turn", {
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "body": JSON.stringify({"prompt": prompt, "session_id": session_id})
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
                if line.startswith("data: ") and not frame.startswith("event:") {
                    chunk = JSON.parse(line[6:]) as str;
                    event = JSON.parse(chunk) as dict[str, any];
                    handle_event(event);
                }
            }
        }
    }
    is_streaming = False;
}

impl app.handle_event(event: dict[str, any]) -> None {
    event_type = event.get("type", "");
    if event_type == "text_delta" {
        delta = event.get("text", "");
        updated_last: dict[str, str] = {**messages[-1]};
        updated_last["text"] = updated_last["text"] + delta;
        messages = messages[:-1] + [updated_last];
        return;
    }
    if event_type == "text_final" {
        updated_last: dict[str, str] = {**messages[-1]};
        if updated_last["text"] == "" {
            updated_last["text"] = event.get("text", "");
            messages = messages[:-1] + [updated_last];
        }
        return;
    }
    if event_type == "tool_use" {
        updated_last: dict[str, str] = {**messages[-1]};
        note = chr(10) + "[Using " + str(event.get("name", "")) + "...]" + chr(10);
        updated_last["text"] = updated_last["text"] + note;
        messages = messages[:-1] + [updated_last];
        return;
    }
    if event_type == "done" {
        sid = event.get("session_id");
        if sid {
            session_id = sid;
        }
        if event.get("is_error", False) {
            messages = messages + [{"role": "error", "text": str(event.get("result", "The turn ended with an error."))}];
        }
        return;
    }
    if event_type == "error" {
        messages = messages + [{"role": "error", "text": str(event.get("message", ""))}];
        return;
    }
}

impl app.handle_input_change(e: any) -> None {
    input_text = e.target.value;
}

impl app.handle_key_down(e: any) -> None {
    if e.key == "Enter" and not e.shiftKey {
        e.preventDefault();
        handle_send();
    }
}
