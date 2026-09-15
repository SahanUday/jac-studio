"""Lightbulb "Fix"/"Explain"/"Modify" code actions via Monaco's `registerCodeActionProvider`.
Registered for every language (`"*"`), not just `"jac"`, unlike this directory's LSP-backed
providers. Routes through the existing `AIChatApp` sidebar (`onAskAI`, threaded down from
`workbench.jac`) rather than a new chat surface. `autoSend` marks "Fix"/"Explain" as complete
requests sent immediately; "Modify..." only prefills the input box for the user to finish."""

glob _registered: bool = False;

def _fix_prompt(path: str, lang: str, code: str, markers: list[any]) -> str {
    messages = [str(m.message) for m in markers];
    return (
        "Fix the following issue(s) in " + path + ":\n\n"
        + "\n".join(["- " + msg for msg in messages])
        + "\n\nRelevant code:\n```" + lang + "\n" + code + "\n```"
    );
}

def _explain_prompt(path: str, lang: str, code: str) -> str {
    return "Explain what this code does, in " + path + ":\n\n```" + lang + "\n" + code + "\n```";
}

def _modify_prompt(path: str, lang: str, code: str) -> str {
    return "In " + path + ", modify this code:\n\n```" + lang + "\n" + code + "\n```\n\n";
}

def _provide_code_actions(model: any, range: any, context: any) -> dict[str, any] {
    path = model.uri.path;
    lang = model.getLanguageId();
    code = model.getValueInRange(range);
    actions = [];

    markers = context.markers;
    if len(markers) > 0 {
        actions.append({
            "title": "Fix with AI",
            "kind": "quickfix",
            "diagnostics": markers,
            "command": {
                "id": "jac-studio.aiFix",
                "title": "Fix with AI",
                "arguments": [_fix_prompt(path, lang, code, markers), True]
            }
        });
    }
    if not range.isEmpty() {
        actions.append({
            "title": "Explain with AI",
            "kind": "quickfix",
            "command": {
                "id": "jac-studio.aiExplain",
                "title": "Explain with AI",
                "arguments": [_explain_prompt(path, lang, code), True]
            }
        });
        actions.append({
            "title": "Ask AI to modify this...",
            "kind": "quickfix",
            "command": {
                "id": "jac-studio.aiModify",
                "title": "Ask AI to modify this...",
                "arguments": [_modify_prompt(path, lang, code), False]
            }
        });
    }
    return {"actions": actions, "dispose": lambda -> None {}};
}

def:pub register_ai_code_action_provider(monaco: any, onAskAI: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    handler = lambda (accessor: any, promptText: str, autoSend: bool) {
        onAskAI(promptText, autoSend);
    };
    monaco.editor.registerCommand("jac-studio.aiFix", handler);
    monaco.editor.registerCommand("jac-studio.aiExplain", handler);
    monaco.editor.registerCommand("jac-studio.aiModify", handler);

    monaco.languages.registerCodeActionProvider("*", {
        "provideCodeActions": lambda (model: any, range: any, context: any, token: any) {
            return _provide_code_actions(model, range, context);
        }
    });
}
