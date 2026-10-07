impl app.poll -> None {
    branch = await get_git_branch();
    counts = await get_diagnostic_counts();
}

impl app.load_languages -> None {
    languages = list_editor_languages();
}

"""Bumps `tick` so the bar re-reads Monaco, since a changed model option fires no React render."""
impl app.choose(kind: str, value: any) -> None {
    set_editor_option(path, kind, value);
    tick = tick + 1;
}
