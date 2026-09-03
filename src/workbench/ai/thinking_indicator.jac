"""ThinkingIndicator: the spinner + rotating status word + elapsed-time counter shown while a chat
turn is in flight -- matches the real Claude Code CLI/extension's own such indicator (a rotating
whimsical verb like "Pondering… (12s)", not a single static "Thinking…" for the whole turn), shared
by `ai_chat.jac`'s sidebar and `inline_chat_widget.jac`'s popover since both hit the identical need.
Not a byte-for-byte reproduction of Anthropic's own exact internal word list (unverifiable from
here) -- a similarly-spirited rotating set instead, in the same idiom as the real tool's own visible
UI text.

**Always mounted by the parent (`active={is_streaming}`), not conditionally created/destroyed** --
internally renders nothing (a bare `<>` fragment) while `active` is false, and resets its own
`word`/`elapsed` state itself via `useEffect([active])` firing on every false-to-true transition.
This is what makes a brand-new turn start its own elapsed counter back at 0 and pick a fresh word,
without the parent needing to manage a remount key or any of that timing itself -- the same
"parent just passes the current boolean, the leaf owns its own animation state" shape
`monaco_editor.jac`'s cursor-blink-adjacent timers already use elsewhere in this project."""

import from "react" { useState, useEffect }

glob _WORDS: list[str] = [
    "Thinking", "Pondering", "Contemplating", "Cogitating", "Musing", "Noodling", "Percolating",
    "Ruminating", "Mulling", "Processing", "Reasoning", "Considering", "Deliberating", "Puzzling",
    "Synthesizing", "Working", "Brewing", "Cooking", "Crunching", "Reticulating", "Wrangling",
    "Marinating", "Simmering", "Conjuring", "Weaving"
];

def _random_word -> str {
    idx = Math.floor(Math.random() * len(_WORDS)) as int;
    return _WORDS[idx];
}

def:pub app(active: bool) -> JsxElement {
    has word: str = "Thinking";
    has elapsed: int = 0;

    useEffect(lambda {
        if not active {
            return;
        }
        word = _random_word();
        elapsed = 0;
        word_timer = setInterval(lambda { word = _random_word(); }, 2500);
        tick_timer = setInterval(lambda { elapsed = elapsed + 1; }, 1000);
        return lambda {
            clearInterval(word_timer);
            clearInterval(tick_timer);
        };
    }, [active]);

    <>
        {(
            <div style={{"display": "flex", "alignItems": "center", "gap": "0.35rem", "color": "#8C8C8C", "fontSize": "11px", "padding": "0.1rem 0"}}>
                <span className="codicon codicon-loading codicon-modifier-spin" style={{"fontSize": "12px"}} />
                <span>{word + "… (" + str(elapsed) + "s)"}</span>
            </div>
        ) if active else None}
    </>
}
