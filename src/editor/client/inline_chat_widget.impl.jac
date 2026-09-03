"""Builds the actual prompt sent for a turn -- includes the selected code (if any) as context,
the same shape `ai_code_action_provider.jac`'s "Modify" prompt uses, so a user typing "make this
async" gets the surrounding code without having to paste it themselves. Falls back to just the
file path when there's no selection (a cursor-position-only inline chat turn, e.g. "add a
docstring here")."""
def _build_prompt(editor: any, path: str, instruction: str) -> str {
    selection = editor.getSelection();
    if selection and not selection.isEmpty() {
        code = editor.getModel().getValueInRange(selection);
        return "In " + path + ":\n\n```\n" + code + "\n```\n\n" + instruction;
    }
    return "In " + path + ":\n\n" + instruction;
}

"""Consumes `start_chat_turn`'s SSE stream -- the identical `fetch` + `ReadableStream` reading loop
`ai_chat.impl.jac`/`debug_console.impl.jac` already established (two-`JSON.parse` unwrap, the
trailing-`event: end`-frame guard). See `app`'s own docstring for why this widget makes its own
independent call rather than reusing the sidebar's."""
impl app.handle_submit -> None {
    editor = editorRef.current;
    if not editor or input_text.strip() == "" or is_streaming {
        return;
    }
    instruction = input_text;
    input_text = "";
    prompt = _build_prompt(editor, path, instruction);
    response_text = "";
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
        response_text = response_text + event.get("text", "");
        return;
    }
    if event_type == "text_final" {
        if response_text == "" {
            response_text = event.get("text", "");
        }
        return;
    }
    if event_type == "tool_use" {
        response_text = response_text + chr(10) + "[Using " + str(event.get("name", "")) + "...]" + chr(10);
        return;
    }
    if event_type == "done" {
        sid = event.get("session_id");
        if sid {
            session_id = sid;
        }
        if event.get("is_error", False) {
            response_text = response_text + chr(10) + "[Error: " + str(event.get("result", "")) + "]";
        }
        return;
    }
    if event_type == "error" {
        response_text = response_text + chr(10) + "[Error: " + str(event.get("message", "")) + "]";
        return;
    }
    if event_type == "tool_approval_request" {
        card: dict[str, any] = {
            "tool_use_id": event.get("tool_use_id", ""),
            "name": event.get("name", ""),
            "input_text": JSON.stringify(event.get("input", {})),
            "has_diff": event.get("modified_text") is not None,
            "file_path": event.get("input", {}).get("file_path", ""),
            "original_text": event.get("original_text", ""),
            "modified_text": event.get("modified_text", "")
        };
        pending_approvals = pending_approvals + [card];
        return;
    }
}

"""Mirrors `ai_chat.impl.jac`'s own `handle_approval_decision` -- appends the decision as a note
into `response_text` rather than a separate list entry, for the identical reason that module's own
docstring documents (a live-caught bug where a separate entry broke the "text keeps appending to
the current response" invariant `text_delta` depends on)."""
impl app.handle_approval_decision(tool_use_id: str, name: str, decision: str) -> None {
    await approve_tool_call(tool_use_id, decision);
    pending_approvals = [a for a in pending_approvals if a["tool_use_id"] != tool_use_id];
    verb = "Allowed" if decision == "allow" else "Denied";
    response_text = response_text + chr(10) + "[" + verb + " " + name + "]" + chr(10);
}

impl app.handle_input_change(e: any) -> None {
    input_text = e.target.value;
}

impl app.handle_key_down(e: any) -> None {
    if e.key == "Enter" and not e.shiftKey {
        e.preventDefault();
        handle_submit();
        return;
    }
    if e.key == "Escape" {
        e.stopPropagation();
        onClose();
    }
}

"""Resets this popover's own independent conversation on close -- matches `app`'s own docstring
("no resume across a reopen in this first slice"), so reopening Ctrl+I later starts fresh rather
than silently continuing a stale, possibly irrelevant session against whatever the cursor is on
now."""
impl app.handle_close(e: any) -> None {
    input_text = "";
    response_text = "";
    session_id = None;
    pending_approvals = [];
    onClose();
}
