impl app.handle_resize -> None {
    fit = fit_ref.current;
    if not fit {
        return;
    }
    term = term_ref.current;
    if not term {
        return;
    }
    fit.fit();
    if not banner_written_ref.current {
        term.write("jac-studio terminal\r\n$ ");
        banner_written_ref.current = True;
    }
}

impl app.handle_data(data: str) -> None {
    if running {
        return;
    }
    term = term_ref.current;
    if not term {
        return;
    }
    if data == "\r" {
        submit_command();
        return;
    }
    if data == "\x7f" or data == "\b" {
        if len(input_buffer) > 0 {
            input_buffer = input_buffer[:-1];
            term.write("\b \b");
        }
        return;
    }
    if data == "\x03" {
        input_buffer = "";
        term.write("^C\r\n$ ");
        return;
    }
    if ord(data[0]) < 32 {
        return;
    }
    input_buffer = input_buffer + data;
    term.write(data);
}

impl app.submit_command -> None {
    command = input_buffer;
    input_buffer = "";
    term = term_ref.current;
    if not term {
        return;
    }
    term.write("\r\n");
    if command.strip() == "" {
        term.write("$ ");
        return;
    }
    running = True;
    resp = await fetch("/function/run_in_terminal", {
        "method": "POST",
        "headers": {"Content-Type": "application/json"},
        "body": JSON.stringify({"command": command, "cwd": ""})
    });
    reader = resp.body.getReader();
    decoder = new(TextDecoder);
    nl = chr(10);
    buf = "";
    exit_marker = "[process exited with code ";
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
                    term.write(chunk.replace(nl, "\r\n"));
                    if exit_marker in chunk {
                        tail = chunk.split(exit_marker)[1];
                        code_str = tail.split("]")[0].strip();
                        if code_str != "0" and onNotify {
                            onNotify(f"Command failed (exit {code_str}): {command}", "error", "Terminal");
                        }
                    }
                }
            }
        }
    }
    running = False;
    term.write("$ ");
}
