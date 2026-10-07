"""Pure helpers for the Keyboard Shortcuts editor: which commands a search shows, and which other
commands already use a chord."""

import from src.workbench.commands.keybinding_label { format_keybinding }

"""Every word of `query` must appear in the title, id, or any of the command's keys (raw or labelled),
case-insensitively. Sorted by title so the `File:`, `Edit:` ... categories group together."""
def:pub visible_commands(commands: list[dict[str, any]], query: str) -> list[dict[str, any]] {
    words = query.lower().split();
    shown = [];
    for c in commands {
        haystack = c["title"].lower() + " " + c["id"].lower();
        for b in c["keybindings"] {
            haystack += " " + b["key"] + " " + format_keybinding([b]).lower();
        }
        if all([w in haystack for w in words]) {
            shown.append(c);
        }
    }
    return sorted(shown, key=lambda (c: dict[str, any]) { c["title"].lower(); });
}

"""Titles of the other commands bound to `chord`; a duplicate is allowed (VS Code allows it) but flagged."""
def:pub conflicts_for(commands: list[dict[str, any]], chord: str, exclude_id: str) -> list[str] {
    return [
        c["title"] for c in commands
        if c["id"] != exclude_id and any([b["key"] == chord for b in c["keybindings"]])
    ];
}
