impl app.toggle_theme -> None {
    next_theme = "light" if theme == "dark" else "dark";
    await set_setting("workbench.colorTheme", next_theme);
    theme = next_theme;
}
