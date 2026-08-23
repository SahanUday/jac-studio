"""The actual point of this spike: three independently-reached services interacting through
the graph, the way real jac-studio commands will, with no constructor wiring anywhere."""

import time;
import from src.config_service {
    get_config_service, config_set, config_get, _reset_config_service_cache_for_tests
}
import from src.file_tree_service {
    get_file_tree_service, seed_entry, list_entries, _reset_file_tree_service_cache_for_tests
}
import from src.command_registry {
    register_command, run_command, _reset_command_registry_cache_for_tests
}

def contribute_list_root_command {
    register_command(
        "files.listRoot",
        "List Workspace Root",
        lambda { return list_entries(get_file_tree_service()); }
    );
}

test "a contributed command reads FileTreeService, which itself read ConfigService at creation -- three services, zero DI wiring" {
    _reset_config_service_cache_for_tests();
    _reset_file_tree_service_cache_for_tests();
    _reset_command_registry_cache_for_tests();
    config_set("workspace.rootFolderName", "jac-studio");
    svc = get_file_tree_service();
    seed_entry(svc, "src", is_dir=True);
    seed_entry(svc, "README.md");

    contribute_list_root_command();

    result = run_command("files.listRoot");
    assert result == ["src", "README.md"];
    assert get_file_tree_service().root_name == "jac-studio";
}

test "an uncached graph lookup alone is far too slow for a hot path -- measured, not assumed" {
    _reset_config_service_cache_for_tests();
    config_set("editor.tabSize", 4);

    # One raw [root-->[?:ConfigService]] query per iteration -- bypass the cache entirely by
    # resetting it every time, to measure the thing architecture.md actually worried about.
    iterations = 200;
    start = time.perf_counter();
    for _ in range(iterations) {
        _reset_config_service_cache_for_tests();
        config_get("editor.tabSize");
    }
    elapsed = time.perf_counter() - start;
    per_lookup_us = (elapsed / iterations) * 1_000_000;
    print(f"[perf] uncached: {per_lookup_us:.2f}us/call over {iterations} calls");

    # Real measurement on this machine: ~600us/call uncached under `jac run`. That is not a
    # hypothetical -- see docs/architecture.md's updated open-question entry. This assertion
    # just pins "still in the same slow ballpark", not a strict regression gate.
    assert per_lookup_us > 50.0;
}

test "the cached accessor is what actually makes repeated lookups hot-path-safe" {
    _reset_config_service_cache_for_tests();
    config_set("editor.tabSize", 4);
    config_get("editor.tabSize");  # warm the cache once, same as real startup would

    iterations = 5000;
    start = time.perf_counter();
    for _ in range(iterations) {
        config_get("editor.tabSize");
    }
    elapsed = time.perf_counter() - start;
    per_lookup_us = (elapsed / iterations) * 1_000_000;
    print(f"[perf] cached: {per_lookup_us:.2f}us/call over {iterations} calls");

    # A keystroke has roughly a 16ms (60fps) frame budget. Cached reads measured ~0.06us/call
    # on this machine -- assert two orders of magnitude below the uncached number, so this
    # fails loudly if the cache is ever silently removed from get_config_service.
    assert per_lookup_us < 10.0;
}
