"""User-level storage under `$JAC_STUDIO_CONFIG_DIR`, else `$XDG_CONFIG_HOME/jac-studio`, else
`~/.config/jac-studio`: per OS user, not per jac `root`, like VS Code's own user data. Plain JSON
files, so none of the graph persistence traps apply. See ADR 0082."""

import json;
import os;

def:pub user_data_dir -> str {
    configured = os.environ.get("JAC_STUDIO_CONFIG_DIR", "");
    if configured != "" {
        return configured;
    }
    base = os.environ.get("XDG_CONFIG_HOME", "") or os.path.join(os.path.expanduser("~"), ".config");
    return os.path.join(base, "jac-studio");
}

"""`fallback` for a missing or unparseable file -- a corrupt state file must not break startup."""
def:pub read_json_path(path: str, fallback: any) -> any {
    try {
        with open(path, "r") as f {
            return json.load(f);
        }
    } except Exception as e {
        return fallback;
    }
}

"""Writes a temp file then renames, so a crash mid-write never leaves a truncated file."""
def:pub write_json_path(path: str, data: any) -> None {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    tmp = path + ".tmp";
    with open(tmp, "w") as f {
        json.dump(data, f, indent=2);
    }
    os.replace(tmp, path);
}

def:pub read_user_json(name: str, fallback: any) -> any {
    return read_json_path(os.path.join(user_data_dir(), name), fallback);
}

def:pub write_user_json(name: str, data: any) -> None {
    write_json_path(os.path.join(user_data_dir(), name), data);
}
