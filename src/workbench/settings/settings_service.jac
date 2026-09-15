"""Persisted key/value settings store -- one open-ended `values` dict, not a field per setting, so
a new setting never forces a `__jac_schema__` migration.

Cache the jid and re-resolve via `jobj()` immediately before mutating: a `has`-field mutation
through a cached node object is never committed (`2026-08-28-field-mutation-on-cached-node-not-persisted`)."""

node Settings {
    has values: dict[str, any] = {};
}

glob _cached_settings_jid: dict[str, str] = {};

def:pub _reset_settings_cache_for_tests {
    _cached_settings_jid.clear();
}

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
