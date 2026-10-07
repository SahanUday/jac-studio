"""Human label for a command's keybindings, shared by the palette and the menu bar."""

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
    return "+".join([p.capitalize() for p in parts]);
}
