"""The known settings: key, type, default, description, category. The Settings editor renders from
this over RPC and the service validates against it, so a setting exists in exactly one place.
Pure data and functions, no I/O."""

glob:pub SETTINGS: list[dict[str, any]] = [
    {
        "key": "workbench.colorTheme", "type": "enum", "default": "dark", "category": "Workbench",
        "options": ["dark", "light"], "description": "Specifies the color theme used in the workbench."
    },
    {
        "key": "workbench.startupEditor", "type": "enum", "default": "welcomePage", "category": "Workbench",
        "options": ["welcomePage", "none"],
        "description": "Controls which editor is shown at startup when none are restored from the last session."
    },
    {
        "key": "editor.fontSize", "type": "number", "default": 14, "category": "Editor", "min": 6, "max": 100,
        "description": "Controls the font size in pixels."
    },
    {
        "key": "editor.tabSize", "type": "number", "default": 4, "category": "Editor", "min": 1, "max": 16,
        "description": "The number of spaces a tab is equal to."
    },
    {
        "key": "editor.wordWrap", "type": "enum", "default": "off", "category": "Editor", "options": ["off", "on"],
        "description": "Controls how lines should wrap."
    },
    {
        "key": "editor.lineNumbers", "type": "enum", "default": "on", "category": "Editor",
        "options": ["on", "off", "relative"], "description": "Controls the display of line numbers."
    },
    {
        "key": "editor.minimap.enabled", "type": "boolean", "default": True, "category": "Editor",
        "description": "Controls whether the minimap is shown."
    },
    {
        "key": "editor.renderWhitespace", "type": "enum", "default": "none", "category": "Editor",
        "options": ["none", "boundary", "all"], "description": "Controls how the editor should render whitespace characters."
    },
    {
        "key": "editor.formatOnSave", "type": "boolean", "default": False, "category": "Editor",
        "description": "Format a Jac file when saving it, using the language server."
    },
    {
        "key": "terminal.integrated.fontSize", "type": "number", "default": 13, "category": "Terminal",
        "min": 6, "max": 100, "description": "Controls the font size in pixels of the terminal."
    }
];

def:pub setting_def(key: str) -> dict[str, any] | None {
    for s in SETTINGS {
        if s["key"] == key {
            return s;
        }
    }
    return None;
}

def:pub default_settings -> dict[str, any] {
    return {s["key"]: s["default"] for s in SETTINGS};
}

"""Returns an error message, or "" when `value` is acceptable for `key`. A bool is never a number."""
def:pub validate_setting(key: str, value: any) -> str {
    spec = setting_def(key);
    if spec is None {
        return "Unknown setting: " + key;
    }
    kind = spec["type"];
    if kind == "boolean" {
        return "" if isinstance(value, bool) else "Expected true or false.";
    }
    if kind == "number" {
        if isinstance(value, bool) or not isinstance(value, (int, float)) {
            return "Expected a number.";
        }
        if value < spec["min"] or value > spec["max"] {
            return "Must be between " + str(spec["min"]) + " and " + str(spec["max"]) + ".";
        }
        return "";
    }
    if kind == "enum" {
        return "" if value in spec["options"] else "Expected one of: " + ", ".join(spec["options"]) + ".";
    }
    return "" if isinstance(value, str) else "Expected text.";
}

"""Defaults, then user, then workspace. A value that is unknown or fails validation (a hand-edited
file) is skipped, never raised, so one bad line cannot break the app."""
def:pub merge_settings(user: dict[str, any], workspace: dict[str, any]) -> dict[str, any] {
    merged = default_settings();
    for layer in [user, workspace] {
        for (key, value) in layer.items() {
            if validate_setting(key, value) == "" {
                merged[key] = value;
            }
        }
    }
    return merged;
}
