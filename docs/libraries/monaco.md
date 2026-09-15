# monaco-editor — via `@monaco-editor/react` ^4.7.0

What we use it for: the editor engine. Text model, cursor/selection/IME, virtualized rendering,
undo/redo, tokenization, diff view.
Where it's wired in: `src/editor/client/monaco_editor.jac`, `monaco_diff_editor.jac`,
`jac_language.jac`, and the five `jac_*_provider.jac` modules.

## Capabilities we use

| Capability | API | Where |
|---|---|---|
| Editor mounting | `monaco.editor.create`, React `<Editor>` | `monaco_editor.jac` |
| Shared model across editor groups | `path` prop → `getModel(uri) \|\| createModel(...)` | `monaco_editor.jac` |
| Diff view | `<DiffEditor>`, `originalModelPath`/`modifiedModelPath` | `monaco_diff_editor.jac`, `scm_diff_editor.jac` |
| Custom language | `languages.register`, `setMonarchTokensProvider`, `setLanguageConfiguration` | `jac_language.jac` |
| Completion / hover / definition / references / rename | the matching `languages.register*Provider` | `jac_*_provider.jac` |
| Code actions (lightbulb) | `registerCodeActionProvider` | `ai_code_action_provider.jac` |
| CodeLens | `registerCodeLensProvider` | `git_conflict_codelens_provider.jac` |
| Inline widgets anchored at the cursor | `editor.addContentWidget` | `inline_chat_widget.jac` |
| Cross-file navigation | `editor.registerEditorOpener` | `jac_definition_provider.jac` |
| Minimap, breadcrumbs | editor options | `monaco_editor.jac` |

## Available but not yet used

| Capability | API | Possible use |
|---|---|---|
| Ghost-text inline completion | `registerInlineCompletionsProvider` | Copilot-style suggestions — the API is already reachable, no extension host needed |
| Signature help | `registerSignatureHelpProvider` | `jac lsp` already returns this category of data |
| Document/range formatting | `registerDocumentFormattingEditProvider` | `jac lsp` implements `formatting` already |
| Semantic tokens | `registerDocumentSemanticTokensProvider` | richer than the Monarch tokenizer; `jac lsp` implements `semantic_tokens_full` |
| Folding ranges, link detection, colour picker | `registerFoldingRangeProvider`, `registerLinkProvider` | ordinary editor polish |
| Standalone colourization | `editor.colorize`, `editor.tokenize` | rendering code snippets outside an editor instance |

Monaco ships working tokenizers for Python, JavaScript, CSS, JSON and Markdown. It does **not**
know `.jac` or `.toml` — `.jac` is covered by our own Monarch tokenizer, `.toml` is left as
plaintext deliberately.

## Limits and gotchas

- **`keepCurrentModel={True}` is required** on `<Editor>`. Models are shared by path, and the
  default unmount behavior disposes them — closing a tab in one group otherwise destroys the model
  another still-mounted group is rendering. Trade-off: closed tabs' models are never disposed.
- **`<DiffEditor>` uses differently-named props for the same fix** —
  `keepCurrentOriginalModel` *and* `keepCurrentModifiedModel`, both needed, both default `false`.
  Passing the plain editor's `keepCurrentModel` compiles, runs, and is silently ignored.
- **A cold diff renders as plaintext.** `DiffEditor` falls back to the literal language `"text"`
  for any side it creates a model for itself. Pre-create both models in `beforeMount` with the
  empty-string language spelling so its internal `getModel(uri)` check finds them.
- **`editor.addCommand` does not scope a keybinding to its own instance.** With several editors
  mounted, only the last-registered handler for a chord fires, regardless of focus — and passing
  `"editorTextFocus"` does not fix it in a standalone embedding. This silently saved the wrong
  file. Register chords once globally and dispatch via
  `monaco.editor.getEditors().find(hasTextFocus)`.
  `2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance`
- **Standalone Monaco can't apply a `WorkspaceEdit` to a file with no open model** —
  `StandaloneBulkEditService` throws. A project-wide rename therefore applies edits itself
  (`pushEditOperations` for open models, a disk write for closed ones) and returns
  `{"edits": []}` so Monaco doesn't retry. See `jac_rename_provider.jac`.
- **Standalone Monaco has no notion of opening another file's tab.** Without a
  `registerEditorOpener` that returns `True`, go-to-definition into a file that isn't the active
  tab silently does nothing. Returning `True` keeps our own tab state authoritative.
- **`ZoneWidget` is not in the public npm package.** It's an internal VS Code contrib class. Use
  `addContentWidget` (overlaps neighbouring lines instead of pushing them apart).
- **The diff view hardcodes `minimap.enabled = false`** for both panes regardless of options
  passed. Upstream VS Code behaves the same way — not a gap to work around.
- React content reaches Monaco's externally-owned DOM via `ReactDOM.createPortal`.
- **`options.glyphMargin: True` is required** for glyph decorations. Without it,
  `glyphMarginClassName` is accepted and silently never rendered — breakpoints just vanish.
- **Don't use `editor.addAction` to override a built-in command.** `addAction` and the static
  `registerEditorAction` are separate registries, so registering a built-in's id via `addAction`
  adds a duplicate context-menu entry instead of replacing it. See `command_palette_override.jac`.

## Integration conventions in this codebase

These are ours, not Monaco's — but breaking one causes a real regression.

- **Pass `defaultValue`, never a controlled `value`.** A controlled value fights Monaco for text
  ownership on every keystroke, reintroducing the per-keystroke server round-trip that embedding
  Monaco existed to remove. For the same reason, content is never mirrored into `has` state;
  `Ctrl+S` reads `editor.getValue()` on demand from a `Ref`.
- **One editor instance per open tab, hidden with CSS — never conditionally rendered.**
  Conditional rendering remounts Monaco and destroys that file's undo history.
- **Apply `initialCursor` before the mount-time `onCursorChange` fires**, or every restored tab
  reports Monaco's default `(1,1)` and clobbers the position just restored from session state.
- **Diff views that aren't a real tab use a synthetic model URI**, so language auto-detection works
  without colliding with a real open tab's live model. Key it by something unique per view —
  `ai_tool_diff_preview.jac` keys by `tool_use_id`, since several pending approvals can target the
  same file. See `scm_diff_editor.jac`.
- **Send `notify_document_open` after content loads**, not at mount — the language server needs
  real text to index, not an empty placeholder.
- **Two leaks are accepted deliberately**: closed tabs' models are never disposed (the
  `keepCurrentModel` trade-off), and `_focused_editor_handlers` entries are never removed on
  unmount. Correct trade for a local single-user tool; revisit only if that changes.
