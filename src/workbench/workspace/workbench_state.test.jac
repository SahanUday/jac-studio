import os;
import tempfile;

def use_temp_user_dir -> str {
    directory = tempfile.mkdtemp();
    os.environ["JAC_STUDIO_CONFIG_DIR"] = directory;
    return directory;
}

test "push_recent puts the newest first, drops the duplicate and caps the list" {
    assert push_recent(["/a", "/b"], "/c", 10) == ["/c", "/a", "/b"];
    assert push_recent(["/a", "/b", "/c"], "/b", 10) == ["/b", "/a", "/c"];
    assert push_recent(["/a", "/b", "/c"], "/d", 3) == ["/d", "/a", "/b"];
}

test "_tilde abbreviates the home directory and leaves other paths alone" {
    home = os.path.expanduser("~");
    assert _tilde(home) == "~";
    assert _tilde(os.path.join(home, "dev", "vs")) == "~/dev/vs";
    assert _tilde("/opt/work") == "/opt/work";
}

test "recent workspaces round-trip through the state file, newest first" {
    use_temp_user_dir();
    first = tempfile.mkdtemp();
    second = tempfile.mkdtemp();
    add_recent_workspace(first);
    add_recent_workspace(second);
    add_recent_workspace(first);
    recent = list_recent_workspaces();
    assert [r["path"] for r in recent] == [first, second];
    assert recent[0]["name"] == os.path.basename(first);
    assert recent[0]["location"] == _tilde(os.path.dirname(first));
}

test "list_recent_workspaces drops a folder that no longer exists, remove_recent_workspace forgets one" {
    use_temp_user_dir();
    keep = tempfile.mkdtemp();
    gone = tempfile.mkdtemp();
    add_recent_workspace(gone);
    add_recent_workspace(keep);
    os.rmdir(gone);
    assert [r["path"] for r in list_recent_workspaces()] == [keep];
    remove_recent_workspace(keep);
    assert list_recent_workspaces() == [];
}

test "show-welcome defaults on and persists the choice" {
    use_temp_user_dir();
    assert get_show_welcome() == True;
    set_show_welcome(False);
    assert get_show_welcome() == False;
    set_show_welcome(True);
    assert get_show_welcome() == True;
}

test "a corrupt state file reads as defaults instead of raising" {
    directory = use_temp_user_dir();
    with open(os.path.join(directory, "workbench-state.json"), "w") as f {
        f.write("{not json");
    }
    assert list_recent_workspaces() == [];
    assert get_show_welcome() == True;
}
