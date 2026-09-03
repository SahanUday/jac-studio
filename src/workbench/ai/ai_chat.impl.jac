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
    if event_type == "tool_approval_request" {
        card: dict[str, any] = {
            "tool_use_id": event.get("tool_use_id", ""),
            "name": event.get("name", ""),
            "input_text": JSON.stringify(event.get("input", {}))
        };
        pending_approvals = pending_approvals + [card];
        return;
    }
}

"""Sends the user's decision to `claude_code_client.jac`'s `approve_tool_call` (an ordinary RPC
call, not part of the SSE stream -- see `app`'s own docstring for why the approval card and the
message log are kept as separate lists) and removes the resolved card.

**The decision note is appended into `messages[-1]`'s own text, the exact same pattern
`handle_event`'s `tool_use` branch already uses -- not pushed as a new list entry.** Found live,
not assumed: an earlier version pushed a separate `{"role": "tool", ...}` message here, which
silently broke `text_delta`'s own `messages[-1]` append target -- Claude's turn resumes streaming
*after* a tool call resolves, and that continuation text landed on this decision line instead of a
fresh assistant bubble (reproduced live: `"[Allowed Write]Created ..."` concatenated with no
break). Reusing the established in-place-note pattern keeps the last-message-is-the-live-response
invariant every other branch already depends on."""
impl app.handle_approval_decision(tool_use_id: str, name: str, decision: str) -> None {
    await approve_tool_call(tool_use_id, decision);
    pending_approvals = [a for a in pending_approvals if a["tool_use_id"] != tool_use_id];
    verb = "Allowed" if decision == "allow" else "Denied";
    updated_last: dict[str, str] = {**messages[-1]};
    updated_last["text"] = updated_last["text"] + chr(10) + "[" + verb + " " + name + "]" + chr(10);
    messages = messages[:-1] + [updated_last];
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
