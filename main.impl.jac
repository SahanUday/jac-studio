impl app.set_theme(next_theme: str) -> None {
    theme = next_theme;
}

impl app.toggle_theme -> None {
    next_theme = "light" if theme == "dark" else "dark";
    await set_setting("workbench.colorTheme", next_theme);
    theme = next_theme;
}
