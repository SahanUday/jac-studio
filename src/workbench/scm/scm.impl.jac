impl app.refresh_status -> None {
    status = await get_scm_status();
}

impl app.handle_stage(path: str) -> None {
    await stage_path(path);
    await refresh_status();
}

impl app.handle_unstage(path: str) -> None {
    await unstage_path(path);
    await refresh_status();
}

impl app.handle_discard(path: str, is_untracked: bool) -> None {
    if not confirm("Discard changes to this file? This can't be undone.") {
        return;
    }
    await discard_path(path, is_untracked);
    await refresh_status();
}

impl app.handle_stage_all -> None {
    await stage_all();
    await refresh_status();
}

impl app.handle_unstage_all -> None {
    await unstage_all();
    await refresh_status();
}

impl app.handle_message_change(e: any) -> None {
    commit_message = e.target.value;
}

impl app.handle_commit -> None {
    committing = True;
    result = await commit_changes(commit_message);
    committing = False;
    if result["success"] {
        commit_message = "";
        onNotify("Committed to " + status["branch"] + ".", "info", "Source Control");
        await refresh_status();
    } else {
        onNotify(result["error"], "error", "Source Control");
    }
}
