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

**Cache the jid, not the node, and resolve via `jobj()` on every access (2026-08-28) -- a real
finding, not a style preference.** The `jid(root)`-keyed cache pattern from `docs/architecture.md`'s
service-registry section says to cache "the resolved node," but a *node object* reused across
separate requests silently drops any `has`-field mutation made through it: verified live (`jac
browse`, a real `jac run --serve --dev` process kill + restart, not just a page reload) that
`settings.values = updated;` through a cached raw `Settings` object never survived a restart --
`version` stayed `0` in the underlying row forever, confirming the mutation was never durably
committed, even though every *read* within the same live process looked correct (the illusion
that misled this bug into shipping in the first place, in `set_setting`'s first version). Edge
attachment from that same kind of cached object (e.g. `workspace_service.jac`'s
`parent +>:Contains():+> child`) does NOT have this problem -- verified separately, an edge created
through a cross-request cached node survived a real restart. The gap is specific to field
mutations on a reused object, not the caching pattern itself. Re-resolving via `jobj(cached_jid)`
(the `jac-sv-persistence` guide's own canonical "UPDATE" pattern) immediately before mutating fixes
it -- verified live, the identical `set_setting` call through a jid-then-`jobj()` cache survived a
real restart. `jobj()` is documented O(1), so this keeps the whole point of the original cache
(avoiding the ~600us/call `[root-->[?:Type]]` traversal) while actually being correct. See tracker
entry `2026-08-28-field-mutation-on-cached-node-not-persisted` for the full repro and root-cause
writeup, and `docs/architecture.md`'s service-registry section for the corrected caching rule this
also updates.

**First real consumer**: `main.jac`'s `workbench.colorTheme` (`"dark" | "light"`), toggled via the
`workbench.action.toggleColorTheme` command -- proof this isn't just inert data model, the same bar
`command_registry.jac`'s keybinding overrides clear via their own test coverage. Phase 3's later
visual-identity retheme work is what gives `"light"` a real VS-Code-accurate palette to switch to;
this module only owns persisting *which* one is chosen.
"""

node Settings {
    has values: dict[str, any] = {};
}

glob _cached_settings_jid: dict[str, str] = {};

def:pub _reset_settings_cache_for_tests {
    _cached_settings_jid.clear();
}

"""Resolves fresh via `jobj()` on every call, keyed by a cached jid rather than a cached object --
see the module docstring's 2026-08-28 finding. Safe (and required) to call this on every read and
every write: `jobj()` is O(1), so there's no cost reason to special-case reads."""
def get_settings_node -> Settings {
    key = jid(root);
    if key not in _cached_settings_jid {
        existing = [root-->[?:Settings]];
        settings = existing[0] if existing else root ++> Settings();
        _cached_settings_jid[key] = jid(settings);
        return settings;
    }
    return jobj(_cached_settings_jid[key]) as Settings;
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
