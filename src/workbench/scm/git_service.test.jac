import os;
import tempfile;
import subprocess;
import from src.workbench.workspace.workspace_service { _reset_workspace_cache_for_tests, open_workspace }

glob _GIT_ENV: list[str] = [
    "-c", "user.name=Test User",
    "-c", "user.email=test@example.com",
    "-c", "commit.gpgsign=false"
];

def _git(repo_root: str, args: list[str]) -> None {
    subprocess.run(["git"] + _GIT_ENV + args, cwd=repo_root, capture_output=True, text=True, check=True);
}

"""A bare repo with one committed file (`tracked.txt`) and nothing else changed yet -- the common
starting point most tests build further changes on top of."""
def make_repo -> str {
    repo_root = tempfile.mkdtemp();
    _git(repo_root, ["init", "-b", "main"]);
    with open(os.path.join(repo_root, "tracked.txt"), "w") as f {
        f.write("first line\nsecond line\nthird line\n");
    }
    _git(repo_root, ["add", "tracked.txt"]);
    _git(repo_root, ["commit", "-m", "initial commit"]);
    return repo_root;
}

def open_repo(repo_root: str) -> None {
    _reset_workspace_cache_for_tests();
    open_workspace(repo_root);
}

test "no workspace open reports not-a-repo, not an error" {
    _reset_workspace_cache_for_tests();

    status = get_scm_status();

    assert status["is_repo"] == False;
    assert status["staged"] == [];
    assert status["unstaged"] == [];
    assert status["untracked"] == [];
}

test "a workspace that isn't a git repo reports not-a-repo" {
    plain_dir = tempfile.mkdtemp();
    open_repo(plain_dir);

    status = get_scm_status();

    assert status["is_repo"] == False;
}

test "a fresh repo with no changes reports the branch and empty status buckets" {
    repo_root = make_repo();
    open_repo(repo_root);

    status = get_scm_status();

    assert status["is_repo"] == True;
    assert status["branch"] == "main";
    assert status["staged"] == [];
    assert status["unstaged"] == [];
    assert status["untracked"] == [];
}

test "a modified tracked file appears in unstaged with status M" {
    repo_root = make_repo();
    with open(os.path.join(repo_root, "tracked.txt"), "a") as f {
        f.write("a fourth line\n");
    }
    open_repo(repo_root);

    status = get_scm_status();

    assert len(status["unstaged"]) == 1;
    assert status["unstaged"][0]["name"] == "tracked.txt";
    assert status["unstaged"][0]["status"] == "M";
    assert status["staged"] == [];
}

test "a new file is untracked until staged, then reported as staged with status A" {
    repo_root = make_repo();
    new_path = os.path.join(repo_root, "brand_new.txt");
    with open(new_path, "w") as f {
        f.write("hello\n");
    }
    open_repo(repo_root);

    before = get_scm_status();
    assert len(before["untracked"]) == 1;
    assert before["untracked"][0]["name"] == "brand_new.txt";
    assert before["staged"] == [];

    stage_path(new_path);
    after = get_scm_status();
    assert after["untracked"] == [];
    assert len(after["staged"]) == 1;
    assert after["staged"][0]["name"] == "brand_new.txt";
    assert after["staged"][0]["status"] == "A";
}

test "get_diff_content for an unstaged change compares HEAD against the working-tree file" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "w") as f {
        f.write("first line\nCHANGED\nthird line\n");
    }
    open_repo(repo_root);

    diff = get_diff_content(tracked_path, False);

    assert diff["original"] == "first line\nsecond line\nthird line\n";
    assert diff["modified"] == "first line\nCHANGED\nthird line\n";
}

test "get_diff_content for a staged change compares HEAD against the index" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "w") as f {
        f.write("first line\nSTAGED CHANGE\nthird line\n");
    }
    open_repo(repo_root);
    stage_path(tracked_path);

    diff = get_diff_content(tracked_path, True);

    assert diff["original"] == "first line\nsecond line\nthird line\n";
    assert diff["modified"] == "first line\nSTAGED CHANGE\nthird line\n";
}

test "get_diff_content for a new untracked file has empty original content" {
    repo_root = make_repo();
    new_path = os.path.join(repo_root, "brand_new.txt");
    with open(new_path, "w") as f {
        f.write("all new\n");
    }
    open_repo(repo_root);

    diff = get_diff_content(new_path, False);

    assert diff["original"] == "";
    assert diff["modified"] == "all new\n";
}

test "get_line_changes reports a modified line range for a tracked working-tree edit" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "w") as f {
        f.write("first line\nCHANGED\nthird line\n");
    }
    open_repo(repo_root);

    changes = get_line_changes(tracked_path);

    assert len(changes) == 1;
    assert changes[0]["type"] == "modified";
    assert changes[0]["startLine"] == 2;
    assert changes[0]["endLine"] == 2;
}

test "get_line_changes reports an added line range for a purely-appended edit" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "a") as f {
        f.write("a fourth line\n");
    }
    open_repo(repo_root);

    changes = get_line_changes(tracked_path);

    assert len(changes) == 1;
    assert changes[0]["type"] == "added";
    assert changes[0]["startLine"] == 4;
    assert changes[0]["endLine"] == 4;
}

test "stage_path then unstage_path round-trips a file back to unstaged" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "a") as f {
        f.write("a change\n");
    }
    open_repo(repo_root);

    stage_path(tracked_path);
    staged = get_scm_status();
    assert len(staged["staged"]) == 1;
    assert staged["unstaged"] == [];

    unstage_path(tracked_path);
    unstaged = get_scm_status();
    assert unstaged["staged"] == [];
    assert len(unstaged["unstaged"]) == 1;
}

test "discard_path reverts a tracked file's unstaged working-tree change" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "w") as f {
        f.write("clobbered\n");
    }
    open_repo(repo_root);

    discard_path(tracked_path, False);

    with open(tracked_path, "r") as f {
        content = f.read();
    }
    assert content == "first line\nsecond line\nthird line\n";
    assert get_scm_status()["unstaged"] == [];
}

test "discard_path on an untracked file deletes it" {
    repo_root = make_repo();
    new_path = os.path.join(repo_root, "scratch.txt");
    with open(new_path, "w") as f {
        f.write("temp\n");
    }
    open_repo(repo_root);

    discard_path(new_path, True);

    assert not os.path.exists(new_path);
    assert get_scm_status()["untracked"] == [];
}

test "commit_changes with staged changes succeeds and clears the staged bucket" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "a") as f {
        f.write("a committed change\n");
    }
    open_repo(repo_root);
    stage_path(tracked_path);

    result = commit_changes("a real commit message");

    assert result["success"] == True;
    assert get_scm_status()["staged"] == [];
}

test "commit_changes with a blank message fails without committing" {
    repo_root = make_repo();
    tracked_path = os.path.join(repo_root, "tracked.txt");
    with open(tracked_path, "a") as f {
        f.write("a staged change\n");
    }
    open_repo(repo_root);
    stage_path(tracked_path);

    result = commit_changes("   ");

    assert result["success"] == False;
    assert len(get_scm_status()["staged"]) == 1;
}

test "commit_changes with nothing staged fails" {
    repo_root = make_repo();
    open_repo(repo_root);

    result = commit_changes("nothing to commit");

    assert result["success"] == False;
}
