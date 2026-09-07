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
    sent_paths = attached_paths;
    input_text = "";
    attached_paths = [];
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
        "body": JSON.stringify({
            "prompt": prompt,
            "session_id": session_id,
            "cwd": cwd,
            "attached_paths": sent_paths,
            "model": model,
            "permission_mode": permission_mode,
            "effort": effort
        })
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

"""Finds the `tool_step` entry with a matching `tool_use_id` and merges `updates` into it in place
(same shallow-copy-and-replace shape every other `messages`/`pending_approvals` mutation in this
file already uses). Returns whether a match was found, so a caller can fall back if the step
somehow isn't there -- a defensive check, not an expected path, since `tool_use_start` always
creates the step before `tool_use_input`/`tool_result` can reference its id."""
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

"""Collapsed by default (`tool_use_start` sets `expanded: False`) -- click the card's header row
to see the full input/result. Reuses `update_tool_step` rather than a bespoke lookup, at the cost
of one extra scan to read the current value before flipping it -- this list is at most a handful of
entries long, not a hot path worth a second bookkeeping structure for."""
impl app.toggle_tool_step_expanded(tool_use_id: str) -> None {
    current = [m for m in messages if m.get("kind") == "tool_step" and m["tool_use_id"] == tool_use_id];
    if len(current) == 0 {
        return;
    }
    update_tool_step(tool_use_id, {"expanded": not current[0].get("expanded", False)});
}

"""Sends the user's decision to `claude_code_client.jac`'s `approve_tool_call` (an ordinary RPC
call, not part of the SSE stream -- see `app`'s own docstring for why the approval card and the
message log are kept as separate lists) and removes the resolved card.

**No longer writes a local note into `messages` at all -- see `app`'s own docstring for why.** The
launcher always follows a decision with a real `tool_result` event (a genuine execution outcome for
an allow, or the SDK's own synthetic denial `ToolResultBlock` for a deny -- confirmed live via a
direct `can_use_tool`-denial probe), which lands on the matching `tool_step` card through
`handle_event`'s own `tool_result` branch. A second, local, optimistic note here would be redundant
with that authoritative update and could race it -- this method's only remaining job is forwarding
the decision and clearing the resolved approval card."""
impl app.handle_approval_decision(tool_use_id: str, decision: str) -> None {
    await approve_tool_call(tool_use_id, decision);
    pending_approvals = [a for a in pending_approvals if a["tool_use_id"] != tool_use_id];
}

"""Typing `@` as the last character opens the attach-file picker (`attach_open`), reusing
`workspace_service.jac`'s own `list_all_files` the same way `quick_open.jac`'s Ctrl+P picker
already does -- matches the trigger character real Copilot/Claude Code chat inputs use for a file
mention, without needing a full Monaco-editor-backed dynamic-variable system (real VS Code's own
mechanism, confirmed by reading `chatDynamicVariables.ts` in a real checkout before choosing this
scoped-down equivalent -- see `claude_code_client.jac`'s `_build_prompt_with_attachments` docstring
for the rest of that finding) for what's, here, a plain `<textarea>`."""
impl app.handle_input_change(e: any) -> None {
    input_text = e.target.value;
    if input_text.endswith("@") {
        attach_open = True;
    }
}

impl app.refresh_attach_files -> None {
    attach_files = await list_all_files();
}

"""Adds `path` to `attached_paths` (deduplicated -- selecting the same file twice is a no-op, not
a second chip) and strips the trailing `@` that opened the picker off `input_text`, so the mention
character doesn't linger as literal text once the file it was standing in for has a real chip of
its own."""
impl app.handle_attach_select(path: str) -> None {
    if path not in attached_paths {
        attached_paths = attached_paths + [path];
    }
    if input_text.endswith("@") {
        input_text = input_text[:-1];
    }
    attach_open = False;
}

impl app.remove_attached_file(path: str) -> None {
    attached_paths = [p for p in attached_paths if p != path];
}

impl app.handle_key_down(e: any) -> None {
    if e.key == "Enter" and not e.shiftKey {
        e.preventDefault();
        handle_send();
    }
}
