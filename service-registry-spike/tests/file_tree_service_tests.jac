import from src.file_tree_service {
    FileTreeService, get_file_tree_service, seed_entry, list_entries,
    _reset_file_tree_service_cache_for_tests
}
import from src.config_service { config_set, _reset_config_service_cache_for_tests }

test "get_file_tree_service is idempotent" {
    _reset_file_tree_service_cache_for_tests();
    first = get_file_tree_service();
    second = get_file_tree_service();
    assert jid(first) == jid(second);
    assert len([root-->[?:FileTreeService]]) == 1;
}

test "seed_entry does not duplicate an entry seeded twice" {
    _reset_file_tree_service_cache_for_tests();
    svc = get_file_tree_service();
    seed_entry(svc, "duplicate-check.txt");
    seed_entry(svc, "duplicate-check.txt");
    names = list_entries(svc);
    assert names.count("duplicate-check.txt") == 1;
}

test "FileTreeService reads its default root name from ConfigService at creation" {
    _reset_file_tree_service_cache_for_tests();
    _reset_config_service_cache_for_tests();
    config_set("workspace.rootFolderName", "my-workspace");
    svc = get_file_tree_service();
    assert svc.root_name == "my-workspace";
}
