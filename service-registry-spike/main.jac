"""Demo wiring for the Phase 0 service-registry spike.

Run with `jac run main.jac` -- registers one contributed command that itself calls through
two other "services" (ConfigService, FileTreeService), all reached via graph queries from
`root`, never through a constructor-injected reference.
"""

import from src.config_service { config_set }
import from src.file_tree_service { get_file_tree_service, seed_entry, list_entries }
import from src.command_registry { register_command, run_command }

def list_workspace_root() -> list[str] {
    svc = get_file_tree_service();
    return list_entries(svc);
}

def bootstrap() -> None {
    config_set("workspace.rootFolderName", "jac-studio");
    svc = get_file_tree_service();
    seed_entry(svc, "src", is_dir=True);
    seed_entry(svc, "README.md");
    register_command("files.listRoot", "List Workspace Root", list_workspace_root);
}

with entry:__main__ {
    bootstrap();
    result = run_command("files.listRoot");
    print(f"files.listRoot -> {result}");
}
