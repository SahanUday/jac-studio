"""SettingsService: Phase 3's persisted key/value settings store (`docs/roadmap.md`'s "Settings and
keybindings as graph-attached objects" bullet) -- the settings half.
`src/workbench/commands/command_registry.jac`'s `KeybindingOverrides` is the keybindings half, kept
as its own node rather than folded in here since the two serve different consumers on different
lifecycles (see that module's docstring).

Follows the node-vs-obj test from `docs/architecture.md`'s service-registry section: a settings
store only earns its keep by surviving a restart (criterion 1) -- there's no point persisting a
setting that resets itself every time the app reopens -- so `Settings` is a real `node`, not a
cached `obj`. This is the opposite call from `document_service.jac`'s `DocumentBuffer`, made for
the opposite reason: a document buffer explicitly does *not* need to survive a restart, since it
always mirrors a file already on disk, where a setting has no such backing copy anywhere else.

**One `values: dict[str, any]` field, not one graph field per setting.** VS Code's own
`settings.json` is exactly this shape -- an open-ended key/value bag, not a fixed schema -- and
nothing here should force a `__jac_schema__` migration (`jac-sv-persistence`) every time a new
setting is introduced. `get_setting`/`set_setting` read and write one key at a time so callers
never need to know the whole settings shape just to touch the one value they care about.

**First real consumer**: `main.jac`'s `workbench.colorTheme` (`"dark" | "light"`), toggled via the
`workbench.action.toggleColorTheme` command -- proof this isn't just inert data model, the same bar
`command_registry.jac`'s keybinding overrides clear via their own test coverage. Phase 3's later
visual-identity retheme work is what gives `"light"` a real VS-Code-accurate palette to switch to;
this module only owns persisting *which* one is chosen.
"""

node Settings {
    has values: dict[str, any] = {};
}

glob _cached_settings: dict[str, Settings] = {};

def:pub _reset_settings_cache_for_tests {
    _cached_settings.clear();
}

def get_settings_node -> Settings {
    key = jid(root);
    if key in _cached_settings {
        return _cached_settings[key];
    }
    existing = [root-->[?:Settings]];
    settings = existing[0] if existing else root ++> Settings();
    _cached_settings[key] = settings;
    return settings;
}

def:pub get_setting(key: str, fallback: any) -> any {
    settings = get_settings_node();
    return settings.values[key] if key in settings.values else fallback;
}

def:pub set_setting(key: str, value: any) {
    settings = get_settings_node();
    updated = {**settings.values};
    updated[key] = value;
    settings.values = updated;
}
