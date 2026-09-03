"""register_ai_code_action_provider: the AI code-actions bullet from `docs/architecture.md`'s
"Reframed 2026-09-03" AI section -- the lightbulb "Fix"/"Explain"/"Modify" menu Copilot's own
`inlineChatCodeActions.ts` offers (see `docs/research/vscode-copilot-architecture.md`), confirmed
there to be an ordinary `vscode.CodeActionProvider` with no Copilot-specific mechanism at all: every
action just builds a prompt and hands it to a generic "start a chat turn" entry point. Monaco's own
`languages.registerCodeActionProvider` is the identical mechanism, already reachable -- this module
is that provider, and every action it offers routes to the *already-shipped* `start_chat_turn`
(via `AIChatApp`, see `onAskAI`'s own note below), not a new backend concept.

**Registered for every language (`"*"`), not just `"jac"`** -- the same call
`git_conflict_codelens_provider.jac` already made for the identical reason: "Explain this code" or
"Fix this diagnostic" is just as useful in a `.py`/`.md`/`.ts` file as a `.jac` one, unlike the
LSP-backed providers in this directory (completion/hover/definition/references/rename), which are
genuinely jac-specific because `jac lsp` only understands Jac source.

**Routes through `AIChatApp`'s own sidebar panel, not a new backend call or a new UI surface.**
`docs/architecture.md` names inline chat (a Monaco content-widget popover) as a separate, later
item -- until that exists, "hand a constructed prompt to chat" means the one chat surface this
project already has. `onAskAI(promptText, autoSend)` is threaded down from `workbench.jac`
(`editor_tabs.jac` -> `monaco_editor.jac` -> here), the same "leaf reports, parent owns state" prop
shape `onOpenLocation`/`onOpenCommandPalette` already use in this same file -- it switches
`active_view_id` to `"ai_chat"` and hands the prompt to `AIChatApp` as a new prop pair
(`pendingPrompt`/`pendingNonce`), which that component picks up via `useEffect`. See
`ai_chat.jac`'s own docstring for the receiving half.

**`autoSend` distinguishes a self-contained request from an open-ended one, matching upstream's own
`autoSend: true/false` distinction on `editorChat.start(...)` (confirmed in the research doc's own
reading of `inlineChatCodeActions.ts`).** "Fix" and "Explain" are complete requests the moment
they're built (a diagnostic's own text, or the selected code) -- sent immediately. "Modify..." only
prefills an instruction template around the selection; the user still has to say *what* to change,
so it's deliberately left in the input box, unsent, for them to finish.

**Idempotent by the same `_registered` guard every other provider in this directory uses** --
`onAskAI` is captured once at first registration, the same established shape
`jac_definition_provider.jac`'s own `onOpenLocation` capture already relies on (that module's
docstring covers why a single capture holds up: the callback is a stable method reference that
reads live component state on each call, not a value snapshotted at registration time)."""

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
            "title": "Fix with Claude Code",
            "kind": "quickfix",
            "diagnostics": markers,
            "command": {
                "id": "jac-studio.aiFix",
                "title": "Fix with Claude Code",
                "arguments": [_fix_prompt(path, lang, code, markers), True]
            }
        });
    }
    if not range.isEmpty() {
        actions.append({
            "title": "Explain with Claude Code",
            "kind": "quickfix",
            "command": {
                "id": "jac-studio.aiExplain",
                "title": "Explain with Claude Code",
                "arguments": [_explain_prompt(path, lang, code), True]
            }
        });
        actions.append({
            "title": "Ask Claude Code to modify this...",
            "kind": "quickfix",
            "command": {
                "id": "jac-studio.aiModify",
                "title": "Ask Claude Code to modify this...",
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
