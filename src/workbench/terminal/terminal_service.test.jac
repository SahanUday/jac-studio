"""Exercises the pure, stateless pieces and file-based glue only, same scope as dap_client.test.jac
-- spawning a real PTY needs `[terminal] enabled = true` and was verified live instead. These tests
run under this project's real `jac.toml`, gate off, matching CI and the condition the gating tests
below depend on."""

import asyncio;
import json;
import os;
import shutil;

def _fresh_session_dir -> (str, str) {
    session_id = "test-" + os.urandom(8).hex();
    session_dir = _session_dir(session_id);
    os.makedirs(session_dir, exist_ok=True);
    return (session_id, session_dir);
}

def _read_input_commands(session_dir: str) -> list[dict[str, any]] {
    path = os.path.join(session_dir, "input.log");
    if not os.path.exists(path) {
        return [];
    }
    with open(path, "r") as f {
        return [json.loads(line) for line in f if line.strip()];
    }
}

test "_valid_session_id accepts a plausible generated id" {
    assert _valid_session_id("66987c95-bdc6-4d6d-ad61-d8e413f20132");
}

test "_valid_session_id rejects a path-traversal attempt" {
    assert not _valid_session_id("../../etc/passwd");
}

test "_valid_session_id rejects an empty string" {
    assert not _valid_session_id("");
}

test "_valid_session_id rejects an id shorter than 8 characters" {
    assert not _valid_session_id("short");
}

test "_valid_session_id rejects a slash even inside an otherwise-plausible id" {
    assert not _valid_session_id("abcd1234/etc");
}

test "_session_dir joins the sessions root and the id" {
    session_dir = _session_dir("abcd1234");
    assert session_dir.endswith(os.path.join("jac_studio_terminal_sessions", "abcd1234"));
}

test "_build_pythonpath joins non-empty sys.path entries with the OS path separator" {
    result = _build_pythonpath(["/a", "", "/b/c", ""]);
    assert result == "/a" + os.pathsep + "/b/c";
}

test "_build_pythonpath returns an empty string for an all-empty sys.path" {
    assert _build_pythonpath(["", ""]) == "";
}

test "_daemon_pid returns None when no pidfile exists" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        assert _daemon_pid(session_dir) is None;
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "_daemon_alive is True for this test process's own pid" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        with open(os.path.join(session_dir, "daemon.pid"), "w") as f {
            f.write(str(os.getpid()));
        }
        assert _daemon_alive(session_dir);
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "_daemon_alive is False for a pid past any real process id" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        with open(os.path.join(session_dir, "daemon.pid"), "w") as f {
            f.write("999999999");
        }
        assert not _daemon_alive(session_dir);
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "_daemon_alive is False when the session directory was never created" {
    assert not _daemon_alive(_session_dir("never-existed-" + os.urandom(4).hex()));
}

test "_write_input_chunks splits data longer than the chunk size across multiple JSON lines that reassemble exactly" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        payload = "x" * (_INPUT_CHUNK_BYTES + 100);
        _write_input_chunks(session_dir, payload);
        commands = _read_input_commands(session_dir);
        assert len(commands) == 2;
        assert all(c["type"] == "input" for c in commands);
        assert "".join(c["data"] for c in commands) == payload;
        assert len(commands[0]["data"]) == _INPUT_CHUNK_BYTES;
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "_write_input_chunks writes a single line for data under the chunk size" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        _write_input_chunks(session_dir, "echo hi");
        commands = _read_input_commands(session_dir);
        assert commands == [{"type": "input", "data": "echo hi"}];
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "send_input is a no-op when the terminal gate is off, even for a real session directory" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        asyncio.run(send_input(session_id, "echo hi"));
        assert _read_input_commands(session_dir) == [];
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "resize_session is a no-op when the terminal gate is off" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        asyncio.run(resize_session(session_id, 100, 30));
        assert _read_input_commands(session_dir) == [];
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "close_session still appends its command even when the terminal gate is off -- a kill switch, not new execution" {
    (session_id, session_dir) = _fresh_session_dir();
    try {
        asyncio.run(close_session(session_id));
        commands = _read_input_commands(session_dir);
        assert len(commands) == 1;
        assert commands[0]["type"] == "close";
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

test "send_input rejects an invalid session id without creating a session directory for it" {
    bad_id = "not a valid id!!";
    fake_dir = _session_dir(bad_id);
    assert not os.path.exists(fake_dir);
    asyncio.run(send_input(bad_id, "echo hi"));
    assert not os.path.exists(fake_dir);
}

test "open_session reports disabled and creates nothing when the terminal gate is off" {
    session_id = "test-" + os.urandom(8).hex();
    session_dir = _session_dir(session_id);
    try {
        result = asyncio.run(open_session(session_id, "", 80, 24));
        assert result == {"status": "disabled"};
        assert not os.path.exists(session_dir);
    } finally {
        shutil.rmtree(session_dir, ignore_errors=True);
    }
}

