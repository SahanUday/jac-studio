"""ConfigService: settings reachable from `root`, no DI container.

A fresh `[root-->[?:ConfigService]]` query measured ~600us/call under `jac run` (see the
service-registry-spike README) -- far too slow to re-run on every access on anything
hot-path-shaped. `get_config_service` resolves the node once per root and caches the reference,
the same discipline a constructor-injected DI service gets for free by only being constructed
once.

**Keyed by `jid(root)`, not a single bare value.** `root` is bound to whoever is calling, not a
process-wide constant (a served app resolves a different `root` per authenticated user) -- a
single `glob X | None = None` cache verifiably leaks one user's node into another user's request
in a long-lived server process (see the README and the linked tracker entry). Every *node this
pattern is applied to* should follow the same keyed shape.
"""

node ConfigService {
    has values: dict[str, any] = {};
}

glob _cached_config_services: dict[str, ConfigService] = {};

def:pub get_config_service -> ConfigService {
    key = jid(root);
    if key in _cached_config_services {
        return _cached_config_services[key];
    }
    existing = [root-->[?:ConfigService]];
    svc = existing[0] if existing else root ++> ConfigService();
    _cached_config_services[key] = svc;
    return svc;
}

def:pub _reset_config_service_cache_for_tests {
    _cached_config_services.clear();
}

def:pub config_get(key: str, `default: any = None) -> any {
    svc = get_config_service();
    return svc.values.get(key, `default);
}

def:pub config_set(key: str, value: any) {
    svc = get_config_service();
    svc.values[key] = value;
}
