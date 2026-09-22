impl app.handle_resize -> None {
    fit = fit_ref.current;
    term = term_ref.current;
    if not fit or not term {
        return;
    }
    fit.fit();
    if not started_ref.current {
        started_ref.current = True;
        start_session();
    }
}

impl app.open_search -> None {
    search_open = True;
}

"""Surfaces a failed clipboard read instead of swallowing it -- a blocked `readText()` (permissions, unfocused document) would otherwise look identical to a successful empty-text paste."""
impl app.paste_from_clipboard -> None {
    term = term_ref.current;
    if not term {
        return;
    }
    try {
        text = await navigator.clipboard.readText();  # jac:ignore[E1032,E1001]
        term.paste(text);
    } except Exception as e {
        if onNotify {
            onNotify(f"Couldn't read the clipboard: {e}", "error", "Terminal");
        }
    }
}

impl app.close_search -> None {
    search_open = False;
    search_query = "";
    search_addon = search_addon_ref.current;
    if search_addon {
        search_addon.clearDecorations();
    }
    term = term_ref.current;
    if term {
        term.focus();
    }
}

"""Enter finds next, Shift+Enter finds previous, Escape closes -- xterm's own keydown handler never sees these since focus is on this input."""
impl app.handle_search_key(e: any) -> None {
    search_addon = search_addon_ref.current;
    if not search_addon {
        return;
    }
    if e.key == "Escape" {
        close_search();
        return;
    }
    if e.key == "Enter" {
        if e.shiftKey {
            search_addon.findPrevious(search_query);
        } else {
            search_addon.findNext(search_query);
        }
    }
}

impl app.handle_data(data: str) -> None {
    session_id = session_id_ref.current;
    if not session_id {
        return;
    }
    send_input(session_id, data);
}

impl app.handle_terminal_resize(size: any) -> None {
    session_id = session_id_ref.current;
    if not session_id {
        return;
    }
    resize_session(session_id, size.cols, size.rows);
}

"""Opens/reattaches the session, then consumes `attach_session`'s SSE stream via a raw `fetch` -- RPC stubs cannot consume a stream."""
impl app.start_session -> None {
    term = term_ref.current;
    if not term {
        return;
    }
    session_id = session_id_ref.current or "";
    ws = await get_current_workspace();
    cwd = ws["root_path"] if ws is not None else "";

    result = await open_session(session_id, cwd, term.cols, term.rows);
    status = result.get("status") if result else "error";
    if status == "disabled" {
        term.write("Terminal is disabled. Set [terminal] enabled = true in jac.toml to turn it on.\r\n");
        return;
    }
    if status == "error" or status == "invalid_session_id" {
        message = result.get("message", "Failed to start the terminal session.") if result else "Failed to start the terminal session.";
        term.write(f"{message}\r\n");
        if onNotify {
            onNotify(message, "error", "Terminal");
        }
        return;
    }

    resp = await fetch("/function/attach_session", {
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "body": JSON.stringify({"session_id": session_id})
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
        frames = buf.split(nl + nl);
        buf = frames.pop();
        for frame in frames {
            for line in frame.split(nl) {
                if line.startswith("data: ") and not frame.startswith("event:") {
                    chunk = JSON.parse(line[6:]) as str;
                    term.write(chunk);
                }
            }
        }
    }
}
