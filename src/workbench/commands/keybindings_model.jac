"""Pure rules for `keybindings.json`, VS Code's format: a list of `{key, command, when}`; a `command`
starting with `-` removes that command's default binding for `key`. Later rules win. A chord is
modifiers in `ctrl`, `shift`, `alt` order then one key, e.g. `ctrl+shift+p`; sequences
(`ctrl+k ctrl+s`) are not supported."""

glob:pub MODIFIERS: list[str] = ["ctrl", "shift", "alt"];

glob _MODIFIER_ALIASES: dict[str, str] = {"cmd": "ctrl", "meta": "ctrl", "control": "ctrl", "option": "alt"};

"""The canonical chord, or `""` when `key` is not a single, well-formed chord."""
def:pub normalize_key(key: str) -> str {
    text = key.strip().lower();
    if text == "" or " " in text {
        return "";
    }
    parts = text.split("+");
    final = parts[-1];
    if final == "" or final in MODIFIERS or final in _MODIFIER_ALIASES {
        return "";
    }
    mods = set();
    for part in parts[:-1] {
        mod = _MODIFIER_ALIASES.get(part, part);
        if mod not in MODIFIERS {
            return "";
        }
        mods.add(mod);
    }
    return "+".join([m for m in MODIFIERS if m in mods] + [final]);
}

def:pub key_error(key: str) -> str {
    if key.strip() == "" {
        return "Press a key combination.";
    }
    if " " in key.strip() {
        return "Key sequences such as Ctrl+K Ctrl+S are not supported.";
    }
    return "" if normalize_key(key) != "" else "That is not a valid key combination.";
}

def _base(command: str) -> str {
    return command[1:] if command.startswith("-") else command;
}

"""One command's bindings: its defaults, minus any a `-command` rule removes, plus the user's additions.
Rules that are malformed are skipped rather than raised, so a hand-edit can't break startup."""
def:pub resolve_command_keybindings(
    command_id: str, defaults: list[dict[str, str]], rules: list[any]
) -> list[dict[str, str]] {
    bindings = [{"key": d["key"], "when": d["when"], "source": "default"} for d in defaults];
    for rule in rules {
        if not isinstance(rule, dict) or not isinstance(rule.get("command"), str) or not isinstance(rule.get("key"), str) {
            continue;
        }
        key = normalize_key(rule["key"]);
        if key == "" {
            continue;
        }
        if rule["command"] == "-" + command_id {
            bindings = [b for b in bindings if b["key"] != key];
        } elif rule["command"] == command_id {
            when = rule.get("when", "") if isinstance(rule.get("when", ""), str) else "";
            if not any([b["key"] == key and b["when"] == when for b in bindings]) {
                bindings.append({"key": key, "when": when, "source": "user"});
            }
        }
    }
    return bindings;
}

def:pub is_modified(command_id: str, rules: list[any]) -> bool {
    return any([isinstance(r, dict) and isinstance(r.get("command"), str) and _base(r["command"]) == command_id for r in rules]);
}

def:pub rules_without_command(rules: list[any], command_id: str) -> list[any] {
    return [
        r for r in rules
        if not (isinstance(r, dict) and isinstance(r.get("command"), str) and _base(r["command"]) == command_id)
    ];
}

"""Leaves the command unbound: every default key gets a `-command` removal."""
def:pub rules_cleared(rules: list[any], command_id: str, defaults: list[dict[str, str]]) -> list[any] {
    return rules_without_command(rules, command_id) + [{"key": d["key"], "command": "-" + command_id} for d in defaults];
}

"""Replaces the command's bindings with `key` (and `when`, when non-empty)."""
def:pub rules_with_binding(
    rules: list[any], command_id: str, defaults: list[dict[str, str]], key: str, when: str
) -> list[any] {
    rule = {"key": normalize_key(key), "command": command_id};
    if when != "" {
        rule["when"] = when;
    }
    return rules_cleared(rules, command_id, defaults) + [rule];
}
