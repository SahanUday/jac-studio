"""Pure helpers behind the Settings editor: display titles, search matching, category list and the
value a scope shows. No state, no RPC."""

"""`editor.minimap.enabled` -> `Editor: Minimap Enabled`: the schema's category, then every key segment
after the first, camelCase spaced."""
def:pub setting_title(spec: dict[str, any]) -> str {
    words = [];
    for part in spec["key"].split(".")[1:] {
        spaced = "";
        for ch in part {
            if ch.lower() != ch and spaced != "" {
                spaced += " ";
            }
            spaced += ch;
        }
        words.append(spaced[:1].upper() + spaced[1:]);
    }
    return spec["category"] + ": " + " ".join(words);
}

"""Every word of `query` must appear in the key, title or description, case-insensitively."""
def:pub matches_query(spec: dict[str, any], query: str) -> bool {
    haystack = (spec["key"] + " " + setting_title(spec) + " " + spec["description"]).lower();
    for word in query.lower().split() {
        if word not in haystack {
            return False;
        }
    }
    return True;
}

def:pub categories_of(schema: list[dict[str, any]]) -> list[dict[str, any]] {
    counts: dict[str, int] = {};
    for spec in schema {
        counts[spec["category"]] = counts.get(spec["category"], 0) + 1;
    }
    return [{"name": name, "count": counts[name]} for name in counts.keys()];
}

def:pub visible_settings(schema: list[dict[str, any]], query: str, category: str) -> list[dict[str, any]] {
    return [s for s in schema if matches_query(s, query) and (category == "" or s["category"] == category)];
}

"""What `scope`'s tab shows for `spec`: its own value if set, else what it inherits (workspace inherits
the user value), else the default."""
def:pub shown_value(spec: dict[str, any], scope: str, user: dict[str, any], workspace: dict[str, any]) -> any {
    key = spec["key"];
    if scope == "workspace" and key in workspace {
        return workspace[key];
    }
    if key in user {
        return user[key];
    }
    return spec["default"];
}

def:pub is_modified(spec: dict[str, any], scope: str, user: dict[str, any], workspace: dict[str, any]) -> bool {
    return spec["key"] in (user if scope == "user" else workspace);
}
