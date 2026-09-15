"""Renders chat message text as markdown; shared by `ai_chat.jac` and `inline_chat_widget.jac`.
Styled through `react-markdown`'s `components` override map, since it ships no styling of its own
and this project uses inline styles rather than CSS classes.
The import must be `{ default as Markdown }` -- the package's resolved entry point exports it only
as the default, so a plain named import compiles but fails to link at runtime (E7001)."""

import from "react-markdown" { default as Markdown }

glob _HEADING_STYLE: dict[str, str] = {
    "margin": "0.5rem 0 0.2rem",
    "fontSize": "12px",
    "fontWeight": "600",
    "color": "#CCCCCC"
};

def _Heading(props: any) -> JsxElement {
    <div style={_HEADING_STYLE}>{props["children"]}</div>
}

def _Paragraph(props: any) -> JsxElement {
    <p style={{"margin": "0 0 0.4rem", "whiteSpace": "pre-wrap", "wordBreak": "break-word"}}>{props["children"]}</p>
}

def _CodeSpan(props: any) -> JsxElement {
    <code style={{"background": "#2A2B2C", "padding": "0.05rem 0.3rem", "borderRadius": "3px", "fontFamily": "monospace", "fontSize": "0.92em", "color": "#CE9178"}}>
        {props["children"]}
    </code>
}

def _CodeBlock(props: any) -> JsxElement {
    <pre style={{"background": "#1E1E1E", "border": "1px solid #2A2B2C", "borderRadius": "4px", "padding": "0.5rem", "overflow": "auto", "margin": "0.3rem 0"}}>
        {props["children"]}
    </pre>
}

def _List(props: any) -> JsxElement {
    <ul style={{"margin": "0 0 0.4rem", "paddingLeft": "1.2rem"}}>{props["children"]}</ul>
}

def _OrderedList(props: any) -> JsxElement {
    <ol style={{"margin": "0 0 0.4rem", "paddingLeft": "1.2rem"}}>{props["children"]}</ol>
}

def _ListItem(props: any) -> JsxElement {
    <li style={{"margin": "0.1rem 0"}}>{props["children"]}</li>
}

def _Link(props: any) -> JsxElement {
    <a href={props["href"]} target="_blank" rel="noopener noreferrer" style={{"color": "#3794FF", "textDecoration": "underline"}}>
        {props["children"]}
    </a>
}

def _Blockquote(props: any) -> JsxElement {
    <blockquote style={{"margin": "0.3rem 0", "padding": "0 0.6rem", "borderLeft": "2px solid #3A3A3A", "color": "#8C8C8C"}}>
        {props["children"]}
    </blockquote>
}

glob _COMPONENTS: dict[str, any] = {
    "h1": _Heading, "h2": _Heading, "h3": _Heading, "h4": _Heading, "h5": _Heading, "h6": _Heading,
    "p": _Paragraph,
    "code": _CodeSpan,
    "pre": _CodeBlock,
    "ul": _List,
    "ol": _OrderedList,
    "li": _ListItem,
    "a": _Link,
    "blockquote": _Blockquote
};

def:pub app(text: str) -> JsxElement {
    <Markdown components={_COMPONENTS}>{text}</Markdown>
}
