"""Raw `fetch` over the SSE stream, not an RPC stub: needs the two-`JSON.parse` unwrap and the
`event:` guard against jaclang's trailing `event: end` frame (as in `debug_console.impl.jac`)."""
impl app.handle_send -> None {
    if not (input_text.strip() != "" and not is_streaming) {
        return;
    }
    prompt = input_text;
    input_text = "";
    messages = messages + [
        {"kind": "text", "role": "user", "text": prompt},
        {"kind": "text", "role": "assistant", "text": ""}
    ];
    is_streaming = True;

    ws = await get_current_workspace();
    cwd = ws["root_path"] if ws is not None else None;

    resp = await fetch("/function/start_chat_turn", {
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "body": JSON.stringify({"prompt": prompt, "session_id": session_id, "cwd": cwd})
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
        last_is_open_text = len(messages) > 0 and messages[-1].get("kind") == "text" and messages[-1]["role"] == "assistant";
        if last_is_open_text {
            updated_last: dict[str, any] = {**messages[-1]};
            updated_last["text"] = updated_last["text"] + delta;
            messages = messages[:-1] + [updated_last];
        } else {
            messages = messages + [{"kind": "text", "role": "assistant", "text": delta}];
        }
        return;
    }
    if event_type == "text_final" {
        last_is_empty_text = len(messages) > 0 and messages[-1].get("kind") == "text" and messages[-1]["role"] == "assistant" and messages[-1]["text"] == "";
        if last_is_empty_text {
            updated_last: dict[str, any] = {**messages[-1]};
            updated_last["text"] = event.get("text", "");
            messages = messages[:-1] + [updated_last];
        }
        return;
    }
    if event_type == "tool_use_start" {
        step: dict[str, any] = {
            "kind": "tool_step",
            "tool_use_id": event.get("tool_use_id", ""),
            "name": event.get("name", ""),
            "input": {},
            "status": "running",
            "result_text": "",
            "expanded": False
        };
        messages = messages + [step];
        return;
    }
    if event_type == "tool_use_input" {
        update_tool_step(event.get("tool_use_id", ""), {"input": event.get("input", {})});
        return;
    }
    if event_type == "tool_result" {
        is_error = event.get("is_error", False);
        update_tool_step(event.get("tool_use_id", ""), {
            "status": "error" if is_error else "done",
            "result_text": str(event.get("content", ""))
        });
        return;
    }
    if event_type == "done" {
        sid = event.get("session_id");
        if sid {
            session_id = sid;
        }
        if event.get("is_error", False) {
            messages = messages + [{"kind": "text", "role": "error", "text": str(event.get("result", "The turn ended with an error."))}];
        }
        return;
    }
    if event_type == "error" {
        messages = messages + [{"kind": "text", "role": "error", "text": str(event.get("message", ""))}];
        return;
    }
    if event_type == "tool_approval_request" {
        has_diff = event.get("modified_text") is not None;
        tool_input = event.get("input", {});
        card: dict[str, any] = {
            "tool_use_id": event.get("tool_use_id", ""),
            "name": event.get("name", ""),
            "input_text": JSON.stringify(tool_input),
            "has_diff": has_diff,
            "file_path": tool_input.get("file_path", ""),
            "original_text": event.get("original_text", ""),
            "modified_text": event.get("modified_text", "")
        };
        pending_approvals = pending_approvals + [card];
        return;
    }
}

"""Merges `updates` into the matching `tool_step`; returns whether one was found."""
impl app.update_tool_step(tool_use_id: str, updates: dict[str, any]) -> bool {
    for (i, m) in enumerate(messages) {
        if m.get("kind") == "tool_step" and m["tool_use_id"] == tool_use_id {
            updated: dict[str, any] = {**m, **updates};
            messages = messages[:i] + [updated] + messages[i + 1:];
            return True;
        }
    }
    return False;
}

impl app.toggle_tool_step_expanded(tool_use_id: str) -> None {
    current = [m for m in messages if m.get("kind") == "tool_step" and m["tool_use_id"] == tool_use_id];
    if len(current) == 0 {
        return;
    }
    update_tool_step(tool_use_id, {"expanded": not current[0].get("expanded", False)});
}

"""Forwards the decision and clears the card only -- the launcher's own `tool_result` event
carries the real outcome, so a local note here would race that authoritative update."""
impl app.handle_approval_decision(tool_use_id: str, decision: str) -> None {
    await approve_tool_call(tool_use_id, decision);
    pending_approvals = [a for a in pending_approvals if a["tool_use_id"] != tool_use_id];
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
