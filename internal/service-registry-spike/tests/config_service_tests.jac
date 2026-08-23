import from src.config_service {
    ConfigService, get_config_service, config_get, config_set,
    _reset_config_service_cache_for_tests
}

test "get_config_service is idempotent -- no duplicate registration on repeated lookup" {
    _reset_config_service_cache_for_tests();
    first = get_config_service();
    second = get_config_service();
    assert jid(first) == jid(second);
    assert len([root-->[?:ConfigService]]) == 1;
}

test "config_set then config_get round-trips through the same graph-reached instance" {
    _reset_config_service_cache_for_tests();
    config_set("editor.fontSize", 14);
    assert config_get("editor.fontSize") == 14;
}

test "config_get returns the default when the key is unset" {
    _reset_config_service_cache_for_tests();
    assert config_get("nonexistent.key", "fallback") == "fallback";
}
