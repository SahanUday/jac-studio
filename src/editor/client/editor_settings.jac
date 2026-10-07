"""Maps the `editor.*` entries of the effective settings onto Monaco construction options."""

def:pub monaco_options_from_settings(settings: dict[str, any]) -> dict[str, any] {
    return {
        "fontSize": settings.get("editor.fontSize", 14),
        "tabSize": settings.get("editor.tabSize", 4),
        "wordWrap": settings.get("editor.wordWrap", "off"),
        "lineNumbers": settings.get("editor.lineNumbers", "on"),
        "minimap": {"enabled": settings.get("editor.minimap.enabled", True)},
        "renderWhitespace": settings.get("editor.renderWhitespace", "none")
    };
}
