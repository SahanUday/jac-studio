"""Human label for a command's keybindings, shared by the palette, the menu bar and the shortcut editor."""

glob _KEY_LABELS: dict[str, str] = {
    "arrowup": "Up", "arrowdown": "Down", "arrowleft": "Left", "arrowright": "Right",
    "pageup": "PageUp", "pagedown": "PageDown", "plus": "+"
};

def _label(part: str) -> str {
    return _KEY_LABELS.get(part, part.capitalize());
}

"""Prefers the always-on keybinding (`when == ""`) over a context-scoped one, so a shortcut only
live while e.g. the terminal has focus isn't shown as the command's general shortcut."""
def:pub format_keybinding(keybindings: list[dict[str, str]]) -> str {
    if len(keybindings) == 0 {
        return "";
    }
    primary = keybindings[0];
    for kb in keybindings {
        if kb["when"] == "" {
            primary = kb;
            break;
        }
    }
    parts = primary["key"].split("+");
    return "+".join([_label(p) for p in parts]);
}
