"""Settings as `settings.json` files: user scope under the user data dir, workspace scope in
`<workspace>/.jac-studio/settings.json`, merged over the schema defaults (ADR 0084). Per OS user,
not per jac `root`; only the workspace path touches the graph. The old graph `Settings` node is
read once to migrate, then emptied."""

import os;
import from src.workbench.user_data.user_data { user_data_dir, read_json_path, write_json_path }
import from src.workbench.workspace.workspace_service { get_current_workspace }
import from src.workbench.settings.settings_schema { SETTINGS, validate_setting, merge_settings }

node Settings {
    has values: dict[str, any] = {};
}

def:pub _user_file -> str {
    return os.path.join(user_data_dir(), "settings.json");
}

"""`""` when no folder is open: workspace scope doesn't exist then."""
def:pub _workspace_file -> str {
    ws = get_current_workspace();
    if ws is None {
        return "";
    }
    return os.path.join(ws["root_path"], ".jac-studio", "settings.json");
}

def _scope_file(scope: str) -> str {
    return _user_file() if scope == "user" else _workspace_file();
}

"""Anything that isn't a JSON object reads as empty, so a corrupt file can't break startup."""
def _read_scope(path: str) -> dict[str, any] {
    if path == "" {
        return {};
    }
    data = read_json_path(path, {});
    return data if isinstance(data, dict) else {};
}

"""First run after the move off the graph: copy known values across, then empty the node so they
can't resurrect after the user deletes the file. A no-op once `settings.json` exists, and it never
creates a node."""
def _migrate_graph_settings -> None {
    if os.path.exists(_user_file()) {
        return;
    }
    existing = [root-->[?:Settings]];
    if len(existing) == 0 or len(existing[0].values) == 0 {
        return;
    }
    stored = jobj(jid(existing[0])) as Settings;
    carried = {k: v for (k, v) in stored.values.items() if validate_setting(k, v) == ""};
    if len(carried) > 0 {
        write_json_path(_user_file(), carried);
    }
    stored.values = {};
}

def _user_settings -> dict[str, any] {
    _migrate_graph_settings();
    return _read_scope(_user_file());
}

def:pub get_effective_settings -> dict[str, any] {
    return merge_settings(_user_settings(), _read_scope(_workspace_file()));
}

"""Everything the Settings editor needs in one round trip."""
def:pub get_settings_view -> dict[str, any] {
    workspace_file = _workspace_file();
    return {
        "schema": SETTINGS,
        "user": _user_settings(),
        "workspace": _read_scope(workspace_file),
        "effective": get_effective_settings(),
        "hasWorkspace": workspace_file != "",
        "userFile": _user_file(),
        "workspaceFile": workspace_file
    };
}

"""`{"ok": False, "error": ...}` rather than raising, so the editor can show the message inline."""
def:pub update_setting(scope: str, key: str, value: any) -> dict[str, any] {
    if scope not in ["user", "workspace"] {
        return {"ok": False, "error": "Unknown scope: " + scope};
    }
    error = validate_setting(key, value);
    if error != "" {
        return {"ok": False, "error": error};
    }
    path = _scope_file(scope);
    if path == "" {
        return {"ok": False, "error": "Open a folder to change workspace settings."};
    }
    current = _user_settings() if scope == "user" else _read_scope(path);
    current[key] = value;
    write_json_path(path, current);
    return {"ok": True, "error": ""};
}

def:pub reset_setting(scope: str, key: str) -> None {
    path = _scope_file(scope);
    if path == "" or scope not in ["user", "workspace"] {
        return;
    }
    current = _user_settings() if scope == "user" else _read_scope(path);
    if key in current {
        del current[key];
        write_json_path(path, current);
    }
}

"""Creates an empty file so the editor tab opens on something saveable; `""` for workspace scope
with no folder open."""
def:pub ensure_settings_file(scope: str) -> str {
    path = _scope_file(scope);
    if path != "" and not os.path.exists(path) {
        write_json_path(path, {});
    }
    return path;
}

def:pub get_setting(key: str, fallback: any) -> any {
    return get_effective_settings().get(key, fallback);
}

def:pub set_setting(key: str, value: any) -> dict[str, any] {
    return update_setting("user", key, value);
}
