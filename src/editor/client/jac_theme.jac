"""`jac-dark`: `vs-dark` plus VS Code Dark+ colours for the token types `jac lsp` emits. `vs-dark`
styles almost none of them, so without this semantic highlighting is invisible. Must run in
`beforeMount`."""

glob:pub THEME_NAME: str = "jac-dark";

glob _registered: bool = False;

glob SEMANTIC_COLOURS: dict[str, str] = {
    "namespace": "4EC9B0",
    "type": "4EC9B0",
    "class": "4EC9B0",
    "enum": "4EC9B0",
    "interface": "4EC9B0",
    "struct": "4EC9B0",
    "type_parameter": "4EC9B0",
    "parameter": "9CDCFE",
    "variable": "9CDCFE",
    "property": "9CDCFE",
    "enum_member": "4FC1FF",
    "function": "DCDCAA",
    "method": "DCDCAA"
};

def:pub register_jac_theme(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    rules = [{"token": name, "foreground": colour} for (name, colour) in SEMANTIC_COLOURS.items()];
    monaco.editor.defineTheme(THEME_NAME, {"base": "vs-dark", "inherit": True, "rules": rules, "colors": {}});
}
