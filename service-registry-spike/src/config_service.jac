"""ConfigService: settings reachable from `root`, no DI container.

A fresh `[root-->[?:ConfigService]]` query measured ~600us/call under `jac run` (see the
service-registry-spike README) -- far too slow to re-run on every access on anything
hot-path-shaped. `get_config_service` resolves the node once per process and caches the
reference, the same discipline a constructor-injected DI service gets for free by only being
constructed once; every *node this pattern is applied to* should follow the same shape.
"""

node ConfigService {
    has values: dict[str, any] = {};
}

glob _cached_config_service: ConfigService | None = None;

def:pub get_config_service -> ConfigService {
    if _cached_config_service is not None {
        return _cached_config_service;
    }
    existing = [root-->[?:ConfigService]];
    svc = existing[0] if existing else root ++> ConfigService();
    _cached_config_service = svc;
    return svc;
}

def:pub _reset_config_service_cache_for_tests {
    _cached_config_service = None;
}

def:pub config_get(key: str, `default: any = None) -> any {
    svc = get_config_service();
    return svc.values.get(key, `default);
}

def:pub config_set(key: str, value: any) {
    svc = get_config_service();
    svc.values[key] = value;
}
