"""register_jac_language: teaches Monaco about Jac itself.

**Empirically confirmed gap (2026-08-28, Phase 3's syntax-highlighting bullet)**: `docs/roadmap.md`
frames Phase 3's syntax-highlighting work as "largely free via monaco-editor's own bundled
tokenizer/language services ... for the languages Monaco already ships" -- verified live
(`jac browse`, `monaco.editor.colorize`) that this genuinely holds for Python, JavaScript, CSS,
JSON, and Markdown: each produces real multi-class token output (`mtk4`/`mtk6`/`mtk8`/...), not
just a language-id label with no visual effect. But `monaco.languages.getLanguages()` lists 90+
bundled languages and **`jac` is not one of them** (neither is `toml`) -- every `.jac` file in
this very project, opened through `monaco_editor.jac`'s `path` prop, resolved to `plaintext` with
zero tokenization. For a "VS Code reimplemented in Jac" editor, shipping "basic syntax
highlighting" while the project's own dominant file type renders as flat plaintext would leave the
headline feature invisible for the exact files a jac-studio user opens most.

**Resolution: register a real (if intentionally non-exhaustive) Monarch tokenizer for Jac**, not
a TextMate grammar port -- Monaco's own bundled languages are themselves Monarch definitions (see
`monaco-editor/esm/vs/basic-languages/*`), so this matches the grain of what "a language Monaco
ships" actually looks like under the hood, rather than reaching for a heavier mechanism upstream
itself doesn't use for this class of language. Scoped to the constructs `jac-core-cheatsheet` and
this project's own `.jac` files actually use: OSP/declaration keywords (`node`, `edge`, `walker`,
`obj`, `def`, `impl`, `has`, `can`, `visit`, `spawn`, ...), control flow, the primitive type names,
`#` line comments, single/double/triple-quoted strings (docstrings use triple double quotes),
backtick-escaped identifiers (`` `node ``), and Jac's `->`/`::` operators. Not a claim of 100%
grammar fidelity --
match statement guards, walrus, and f-string interpolation braces tokenize as plain strings rather
than nested expressions, an acceptable gap for a highlighting-only concern (no semantic analysis
depends on this).

**A stopgap, by explicit decision, not the final answer.** The real, published
`jaseci-labs.jaclang-extension` VS Code extension ships a genuinely complete `jac.tmLanguage.json`
TextMate grammar (4,937 lines, 224 repository entries) -- far more complete than this file.
`docs/roadmap.md`'s Phase 4 now carries the plan to investigate reusing it (either by loading the
real extension if jac-studio ever gets VS-Code-extension-API compatibility, or via a narrower
`vscode-textmate`/`vscode-oniguruma` bridge into Monaco if not) as a direct replacement for this
module. Don't invest further in this file's grammar completeness in the meantime.

**Registered via `beforeMount`, not `onMount`.** Read `@monaco-editor/react`'s own source
(`node_modules/@monaco-editor/react/dist/index.js`) to confirm the actual model-creation order:
the `<Editor>` component resolves the model (`monaco.editor.getModel(uri) || createModel(...)`)
inside the callback it builds *before* calling `onMount`, but `beforeMount` runs earlier still,
right as the Monaco instance becomes available -- registering the language there guarantees
`monaco.languages.register({id: "jac", extensions: [".jac"]})` has already run by the time any
`.jac`-pathed model is created, so automatic language detection from the `path` prop (the same
mechanism that already gives `.md` files `markdown` for free) picks it up correctly the first
time, with no need to call `setModelLanguage` after the fact.

**Idempotent by a module-level guard**, since `beforeMount` fires once per mounted `<Editor>`/
`<DiffEditor>` instance, not once per app -- re-registering the same language id on every tab open
would either throw or silently no-op depending on Monaco's version, neither of which is worth
relying on.
"""

glob _registered: bool = False;

glob KEYWORDS: list[str] = [
    "node", "edge", "walker", "obj", "def", "impl", "has", "can", "with",
    "entry", "exit", "visit", "disengage", "report", "spawn", "flow", "wait",
    "skip", "del", "include", "root", "here", "visitor", "self", "super",
    "import", "from", "as", "glob", "test", "assert", "return", "if", "elif",
    "else", "for", "in", "while", "try", "except", "finally", "raise",
    "class", "async", "await", "lambda", "and", "or", "not", "is", "pub",
    "priv", "protect", "sem", "by", "match", "case", "yield", "break",
    "continue", "type", "global", "nonlocal", "default"
];

glob CONSTANTS: list[str] = ["True", "False", "None"];

glob TYPE_KEYWORDS: list[str] = [
    "int", "float", "str", "bool", "list", "dict", "set", "tuple", "any",
    "bytes", "JsxElement"
];

def _re(pattern: str) -> any {
    return new(RegExp, pattern);  # jac:ignore[E1053]
}

def:pub register_jac_language(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.languages.register({"id": "jac", "extensions": [".jac"], "aliases": ["Jac", "jac"]});

    monaco.languages.setLanguageConfiguration("jac", {
        "comments": {"lineComment": "#"},
        "brackets": [["{", "}"], ["[", "]"], ["(", ")"]],
        "autoClosingPairs": [
            {"open": "{", "close": "}"},
            {"open": "[", "close": "]"},
            {"open": "(", "close": ")"},
            {"open": "\"", "close": "\""},
            {"open": "'", "close": "'"}
        ]
    });

    monaco.languages.setMonarchTokensProvider("jac", {
        "keywords": KEYWORDS,
        "constants": CONSTANTS,
        "typeKeywords": TYPE_KEYWORDS,
        "tokenizer": {
            "root": [
                [_re("#.*$"), "comment"],
                [_re("`[a-zA-Z_]\\w*"), "identifier"],
                [_re('"""'), "string", "@string_triple_double"],
                [_re("'''"), "string", "@string_triple_single"],
                [_re('"'), "string", "@string_double"],
                [_re("'"), "string", "@string_single"],
                [_re("\\d+\\.\\d+"), "number.float"],
                [_re("\\d+"), "number"],
                [_re("->"), "operator"],
                [_re("::"), "operator"],
                [_re("[a-zA-Z_]\\w*"), {
                    "cases": {
                        "@keywords": "keyword",
                        "@constants": "constant",
                        "@typeKeywords": "type",
                        "@default": "identifier"
                    }
                }],
                [_re("[{}()\\[\\]]"), "@brackets"],
                [_re("[<>=!+\\-*/%&|^~]+"), "operator"],
                [_re("[;,.:]"), "delimiter"]
            ],
            "string_double": [
                [_re('[^\\\\"]+'), "string"],
                [_re("\\\\."), "string.escape"],
                [_re('"'), "string", "@pop"]
            ],
            "string_single": [
                [_re("[^\\\\']+"), "string"],
                [_re("\\\\."), "string.escape"],
                [_re("'"), "string", "@pop"]
            ],
            "string_triple_double": [
                [_re('[^"]+'), "string"],
                [_re('"""'), "string", "@pop"],
                [_re('"'), "string"]
            ],
            "string_triple_single": [
                [_re("[^']+"), "string"],
                [_re("'''"), "string", "@pop"],
                [_re("'"), "string"]
            ]
        }
    });
}
