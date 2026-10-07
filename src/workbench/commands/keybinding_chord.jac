"""Builds the canonical chord string (`ctrl+shift+alt+key`, the format `keybindings.json` and the
registry use) from a keyboard event's parts. Shared by the global key handler and the shortcut
recorder, so what you record is exactly what later matches."""

glob _MODIFIER_KEYS: list[str] = ["control", "shift", "alt", "meta", "altgraph", "os"];

"""`""` for a bare modifier press. The command key (Meta) counts as Ctrl, as the key handler has always treated it."""
def:pub chord_from_event(ctrl: bool, shift: bool, alt: bool, key: str) -> str {
    name = key.lower();
    if name in _MODIFIER_KEYS or name == "" {
        return "";
    }
    if name == " " {
        name = "space";
    } elif name == "+" {
        name = "plus";
    }
    parts = [];
    if ctrl {
        parts.append("ctrl");
    }
    if shift {
        parts.append("shift");
    }
    if alt {
        parts.append("alt");
    }
    parts.append(name);
    return "+".join(parts);
}
