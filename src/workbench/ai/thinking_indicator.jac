"""ThinkingIndicator: spinner + rotating status word + elapsed-time counter shown while a chat turn
streams; shared by `ai_chat.jac` and `inline_chat_widget.jac`.
Always mounted by the parent (`active={is_streaming}`), not conditionally created/destroyed --
renders nothing while inactive and resets its own `word`/`elapsed` via `useEffect([active])` on
each false-to-true transition, so a new turn restarts its counter without a parent-managed remount."""

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
