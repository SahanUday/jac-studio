"""register_jac_language: Monarch tokenizer + language config for `.jac`, which Monaco does not
ship. Must run in `beforeMount`, before any `.jac`-pathed model exists, or detection from the
`path` prop misses it; module-level guard keeps it idempotent across every mounted editor.
Deliberately non-exhaustive -- a stopgap until the real `jac.tmLanguage.json` grammar is bridged
in, so don't invest in its completeness. See `docs/libraries/monaco.md`."""

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
