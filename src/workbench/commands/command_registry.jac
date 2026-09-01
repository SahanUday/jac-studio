"""CommandRegistry: the graph as the contribution registry, per `docs/architecture.md`'s
"Extension nodes ... Contribute Command/View/Menu nodes (the graph *is* the contribution
registry)" -- this is Phase 2's first real consumer of that pattern, promoted (same structural
shape) from the Phase 0 validation in `internal/service-registry-spike/src/command_registry.jac`.

**Metadata lives here; execution doesn't.** A `Command` node holds `command_id`/`title` --
genuinely persistent, query-reachable, multi-consumer state (what the palette lists, what a
future extension could contribute into). *Running* a command is a different question: every
command Phase 2 actually has (split the active editor group, close the active tab, toggle the
terminal) is a client-side workbench UI-state mutation, not something with a server-side effect to
invoke -- so unlike the spike's speculative `_handlers`/`run_command`, this version has no handler
table at all. `src/workbench/command_palette/command_palette.jac` fetches `list_commands()` over
RPC for display and dispatches execution through `workbench.jac`'s own `handle_command`, entirely
client-side. Add a server-side `run_command` here only once a real command needs one.

**Seeded lazily, not from a startup hook.** There's no dynamic extension-loading system yet
(Phase 2 has no `Extension` nodes contributing at runtime), so the fixed Phase 2 command set is
seeded the first time `list_commands` is called in a given `root`'s lifetime -- `register_command`
already de-dupes by id, so reseeding on every call is cheap and idempotent, and needs no explicit
app-boot wiring.

**Keybindings (2026-08-25, `docs/roadmap.md` Phase 2's "when clause" bullet)** -- each `Command`
carries zero or more `{"key", "when"}` pairs, a list rather than one scalar pair because a single
command legitimately wants more than one binding (`workbench.action.terminal.toggle` below has
both an always-on shortcut and one scoped to a specific context). This module still only holds
*metadata*, matching the split above: `workbench.jac` is what actually matches a keydown's combo
string against these, evaluates `when`, and dispatches -- see its docstring for the
context-evaluation layer itself. `when` is a single optionally-`!`-negated context-key name
(`"terminalFocus"`, `"!terminalFocus"`), not a full boolean-expression grammar like upstream's
`src/vs/platform/contextkey` (`&&`/`||` per `vscode-feature-gap-analysis.md`) -- nothing here
needs a compound condition yet, and a single-flag check is a two-line addition to extend into `&&`
later if something ever does.

**Keybinding overrides (2026-08-28, `docs/roadmap.md` Phase 3's "keybindings as graph-attached
objects" bullet)** -- `KeybindingOverrides` is a second, separate root-attached node rather than a
field bolted onto `CommandRegistry`, because it has a different lifecycle: `register_command`
already re-syncs a `Command`'s `title`/`keybindings` from `BUILTIN_COMMANDS` on every call (so a
later code change to a command's *default* binding always wins), and mixing a user's persisted
override into that same resync path would mean every deploy silently reverts it. Keeping the
override store separate, and applying it only at the `list_commands` read boundary (mirroring
upstream's own `keybindings.json`-overrides-`package.json`-contributed-defaults model), means a
built-in default can keep evolving in code without ever touching what a user already customized.
An override for a `command_id` replaces that command's whole `keybindings` list rather than
patching one entry -- nothing here needs upstream's more granular add/remove-one-binding model yet.

**`KeybindingOverrides` caches the jid, not the node, and resolves via `jobj()` before mutating
(2026-08-28).** A raw node object reused across separate requests silently drops any `has`-field
mutation made through it -- verified live against a real `jac run --serve --dev` restart, not just
a page reload; see `settings_service.jac`'s docstring for the full finding and tracker entry
`2026-08-28-field-mutation-on-cached-node-not-persisted`. `get_command_registry`'s own cached
`CommandRegistry` node does **not** need this fix -- it's only ever used for graph traversal
(`[reg->:Contributes:->[?:Command]]`), never field-mutated directly, and traversal reads/edge
creation through a cached object are unaffected by this finding (verified separately). Likewise
`register_command`'s `existing_command.title = title;` is safe as written: `existing_command` comes
from a *fresh* traversal query evaluated fresh on every call, never held in a cross-request cache,
which is the actual distinction this finding turns on.
"""

import threading;

node CommandRegistry {}

node Command {
    has command_id: str;
    has title: str;
    has keybindings: list[dict[str, str]] = [];
}

edge Contributes {}

glob BUILTIN_COMMANDS: list[dict[str, any]] = [
    {"id": "workbench.action.splitEditorRight", "title": "View: Split Editor Right", "keybindings": []},
    {"id": "workbench.action.closeActiveEditor", "title": "View: Close Editor", "keybindings": []},
    {
        "id": "workbench.action.terminal.toggle",
        "title": "View: Toggle Terminal",
        "keybindings": [
            {"key": "ctrl+`", "when": ""},
            {"key": "escape", "when": "terminalFocus"}
        ]
    },
    {
        "id": "workbench.action.output.toggle",
        "title": "View: Toggle Output",
        "keybindings": [{"key": "ctrl+shift+u", "when": ""}]
    },
    {
        "id": "workbench.action.debug.toggle",
        "title": "View: Toggle Debug Console",
        "keybindings": [{"key": "ctrl+shift+y", "when": ""}]
    },
    {
        "id": "workbench.action.showSearch",
        "title": "View: Show Search",
        "keybindings": [{"key": "ctrl+shift+f", "when": ""}]
    },
    {
        "id": "workbench.action.showScm",
        "title": "View: Show Source Control",
        "keybindings": [{"key": "ctrl+shift+g", "when": ""}]
    },
    {"id": "workbench.action.tasks.runTask", "title": "Tasks: Run Task", "keybindings": []},
    {"id": "workbench.action.toggleColorTheme", "title": "Preferences: Toggle Color Theme", "keybindings": []},
    {"id": "workbench.action.quickOpen", "title": "Go to File...", "keybindings": [{"key": "ctrl+p", "when": ""}]},
    {"id": "workbench.action.showCommands", "title": "Show All Commands", "keybindings": [{"key": "ctrl+shift+p", "when": ""}]},
    {"id": "workbench.action.showNotifications", "title": "Notifications: Show", "keybindings": []}
];

node KeybindingOverrides {
    has overrides: dict[str, list[dict[str, str]]] = {};
}

glob _cached_command_registries: dict[str, CommandRegistry] = {};
glob _cached_keybinding_overrides_jid: dict[str, str] = {};

def:pub _reset_keybinding_overrides_cache_for_tests {
    _cached_keybinding_overrides_jid.clear();
}

def get_keybinding_overrides -> KeybindingOverrides {
    key = jid(root);
    if key not in _cached_keybinding_overrides_jid {
        existing = [root-->[?:KeybindingOverrides]];
        overrides_node = existing[0] if existing else root ++> KeybindingOverrides();
        _cached_keybinding_overrides_jid[key] = jid(overrides_node);
        return overrides_node;
    }
    return jobj(_cached_keybinding_overrides_jid[key]) as KeybindingOverrides;
}

"""Replacing, not merging, `keybindings` -- see the module docstring's "Keybinding overrides"
section for why a whole-list replace is the right granularity today."""
def:pub set_keybinding_override(command_id: str, keybindings: list[dict[str, str]]) {
    store = get_keybinding_overrides();
    updated = {**store.overrides};
    updated[command_id] = keybindings;
    store.overrides = updated;
}

def:pub clear_keybinding_override(command_id: str) -> None {
    store = get_keybinding_overrides();
    if command_id not in store.overrides {
        return;
    }
    updated = {**store.overrides};
    del updated[command_id];
    store.overrides = updated;
}

"""Narrows, but does not close, the window for `list_commands`'s check-existing-else-create race
(two genuinely concurrent callers -- `workbench.jac` and `command_palette.jac` both fetch
`list_commands()` from their own `can with entry` on the same page load -- can each pass
`register_command`'s existence check before either finishes creating). **Confirmed insufficient by
itself, live**: `asyncio.to_thread` (`jaclang/runtimelib/serving/app.jac`) does serialize the
Python-level function body correctly, but the actual Postgres commit for a `def:pub` happens in
`_finalize_call_response` *after* the function returns (`jaclang/runtimelib/impl/server.impl.jac`)
-- this lock is released before that commit, so a second call can legitimately start executing
after the first one's Python code finished and still read a pre-commit view of the graph. jaseci's
own docs promise a `SERIALIZABLE`-transaction-plus-replay-from-start mechanism for exactly this
case, but `WriteConflict` is never actually raised anywhere in the current runtime, and
`Session.commit`'s own conflict recovery blindly re-flushes the same (already-decided) writes
rather than re-running the check -- so that promised protection doesn't currently fire either. Kept
because it still narrows the race window for free, but `list_commands` also de-dupes its *return
value* by `command_id` (see there) as the actual guarantee against a user-visible duplicate, since
that's the layer this module can control without reaching into unsupported jaseci transaction
internals."""
glob _registry_lock: threading.Lock = threading.Lock();

def:pub _reset_command_registry_cache_for_tests {
    _cached_command_registries.clear();
}

def get_command_registry -> CommandRegistry {
    key = jid(root);
    if key in _cached_command_registries {
        return _cached_command_registries[key];
    }
    existing = [root-->[?:CommandRegistry]];
    reg = existing[0] if existing else root ++> CommandRegistry();
    _cached_command_registries[key] = reg;
    return reg;
}

"""De-dupes by `command_id` but still syncs `title`/`keybindings` onto an already-persisted node
every call, not just on first creation -- the workspace graph outlives a single dev-server process
(persisted, not in-memory-only), so a `Command` node created under an older build of
`BUILTIN_COMMANDS` would otherwise keep serving whatever metadata it had at creation time forever,
silently ignoring later changes to that command's declared title or keybindings. Caught live: a
`Command` node for `workbench.action.terminal.toggle` created before this file had a `keybindings`
field kept returning `[]` after the field was added, until this fix."""
def register_command(command_id: str, title: str, keybindings: list[dict[str, str]]) -> Command {
    reg = get_command_registry();
    matches = [reg->:Contributes:->[?:Command]];
    for existing_command in matches {
        if existing_command.command_id == command_id {
            existing_command.title = title;
            existing_command.keybindings = keybindings;
            return existing_command;
        }
    }
    fresh = Command(command_id=command_id, title=title, keybindings=keybindings);
    reg +>:Contributes():+> fresh;
    return fresh;
}

"""The lock above narrows but doesn't close the race that can leave two `Command` nodes sharing one
`command_id` (see its docstring for why -- a real, currently-unfixable-upstream gap between when a
`def:pub`'s Python code finishes and when its write actually commits). De-duping here, on the
*read* path, is the actual guarantee: even if the graph ends up holding a duplicate node, the
palette never sees it. Keeps the first match per id and drops the rest, which is safe because any
duplicate was created from the exact same `BUILTIN_COMMANDS` entry, so their fields are identical
-- there's no "which one is more correct" question to resolve."""
def:pub list_commands -> list[dict[str, any]] {
    with _registry_lock {
        for spec in BUILTIN_COMMANDS {
            register_command(spec["id"], spec["title"], spec["keybindings"]);
        }
        reg = get_command_registry();
        commands = [reg->:Contributes:->[?:Command]];
        overrides = get_keybinding_overrides().overrides;
        seen_ids: set[str] = set();
        deduped = [];
        for c in commands {
            if c.command_id in seen_ids {
                continue;
            }
            seen_ids.add(c.command_id);
            keybindings = overrides[c.command_id] if c.command_id in overrides else c.keybindings;
            deduped.append({"id": c.command_id, "title": c.title, "keybindings": keybindings});
        }
        return deduped;
    }
}
