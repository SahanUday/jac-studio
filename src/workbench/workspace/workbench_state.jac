"""Recent workspaces and the welcome-page preference, in `workbench-state.json` under the user
data dir. A missing or corrupt file reads as defaults. See ADR 0082."""

import os;
import from src.workbench.user_data.user_data { read_user_json, write_user_json }

glob RECENT_LIMIT: int = 10;

glob _STATE_FILE: str = "workbench-state.json";

"""Most recent first, no duplicates, capped at `limit`."""
def:pub push_recent(paths: list[str], path: str, limit: int) -> list[str] {
    updated = [path] + [p for p in paths if p != path];
    return updated[:limit];
}

"""`~` for the home directory, as VS Code's welcome page shows locations."""
def:pub _tilde(path: str) -> str {
    home = os.path.expanduser("~");
    if path == home {
        return "~";
    }
    if path.startswith(home + os.sep) {
        return "~" + path[len(home):];
    }
    return path;
}

def _load_state -> dict[str, any] {
    state = read_user_json(_STATE_FILE, {});
    return state if isinstance(state, dict) else {};
}

def _save_state(state: dict[str, any]) -> None {
    write_user_json(_STATE_FILE, state);
}

def:pub _recent_paths -> list[str] {
    paths = _load_state().get("recent", []);
    return [p for p in paths if isinstance(p, str)] if isinstance(paths, list) else [];
}

"""Folders that no longer exist are dropped from the list, not shown dead."""
def:pub list_recent_workspaces -> list[dict[str, str]] {
    return [
        {
            "path": p,
            "name": os.path.basename(p.rstrip(os.sep)) or p,
            "location": _tilde(os.path.dirname(p.rstrip(os.sep)))
        }
        for p in _recent_paths() if os.path.isdir(p)
    ];
}

def:pub add_recent_workspace(path: str) -> None {
    state = _load_state();
    state["recent"] = push_recent(_recent_paths(), path, RECENT_LIMIT);
    _save_state(state);
}

def:pub remove_recent_workspace(path: str) -> None {
    state = _load_state();
    state["recent"] = [p for p in _recent_paths() if p != path];
    _save_state(state);
}

def:pub get_show_welcome -> bool {
    return bool(_load_state().get("showWelcomeOnStartup", True));
}

def:pub set_show_welcome(show: bool) -> None {
    state = _load_state();
    state["showWelcomeOnStartup"] = show;
    _save_state(state);
}
