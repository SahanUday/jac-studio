"""The Settings tab: search, User/Workspace scope, category list and one typed control per setting,
rendered from the schema the server returns. Refetches on activation (tabs mount once and hide) and
reports every write through `onChanged` so the workbench re-applies the effective settings.
Number fields commit on blur or Enter, so a half-typed value is never sent. Handlers live in
`settings_editor.impl.jac`."""

import from "react" { useEffect }
import from src.workbench.settings.settings_service { get_settings_view, update_setting, reset_setting }
import from src.workbench.settings.settings_model {
    setting_title, categories_of, visible_settings, shown_value, is_modified
}

glob FIELD_STYLE: dict[str, str] = {
    "background": "#3c3c3c", "border": "1px solid #3c3c3c", "borderRadius": "3px", "color": "#cccccc",
    "padding": "0.3rem 0.5rem", "fontSize": "13px", "colorScheme": "dark"
};

glob LINK_STYLE: dict[str, str] = {
    "background": "none", "border": "none", "color": "#3794ff", "cursor": "pointer", "fontSize": "12px", "padding": "0"
};

def:pub app(active: bool, onChanged: any, onOpenJson: any) -> JsxElement {
    has view: dict[str, any] = {
        "schema": [], "user": {}, "workspace": {}, "effective": {},
        "hasWorkspace": False, "userFile": "", "workspaceFile": ""
    };
    has scope: str = "user";
    has query: str = "";
    has category: str = "";
    has drafts: dict[str, str] = {};
    has errors: dict[str, str] = {};

    async def refresh -> None;
    async def change(key: str, value: any) -> None;
    async def reset(key: str) -> None;
    def set_error(key: str, message: str) -> None;
    def edit_draft(key: str, text: str) -> None;
    async def commit_number(key: str) -> None;

    useEffect(lambda {
        if active {
            refresh();
        }
    }, [active]);

    schema = view["schema"];
    shown = visible_settings(schema, query, category);
    user_values = view["user"];
    workspace_values = view["workspace"];
    categories = categories_of(schema);
    json_label = "Open Settings (JSON)" if scope == "user" else "Open Workspace Settings (JSON)";

    <div style={{"display": "flex", "flexDirection": "column", "height": "100%", "fontFamily": "system-ui, sans-serif", "color": "#cccccc", "colorScheme": "dark"}}>
        <div style={{"padding": "1rem 2rem 0.5rem", "display": "flex", "flexDirection": "column", "gap": "0.7rem"}}>
            <input
                value={query}
                placeholder="Search settings"
                aria-label="Search settings"
                onChange={lambda (e: any) { query = e.target.value; }}
                style={{**FIELD_STYLE, "width": "100%"}}
            />
            <div style={{"display": "flex", "alignItems": "center", "gap": "1.2rem", "borderBottom": "1px solid #2A2B2C"}}>
                {[
                    <button
                        key={s}
                        role="tab"
                        aria-selected={scope == s}
                        disabled={s == "workspace" and not view["hasWorkspace"]}
                        onClick={lambda (e: any) { scope = s; }}
                        style={{
                            "background": "none", "border": "none", "padding": "0.3rem 0.1rem", "fontSize": "13px",
                            "cursor": "pointer" if (s == "user" or view["hasWorkspace"]) else "not-allowed",
                            "color": "#ffffff" if scope == s else "#8C8C8C",
                            "opacity": "1" if (s == "user" or view["hasWorkspace"]) else "0.5",
                            "borderBottom": "2px solid #3794ff" if scope == s else "2px solid transparent"
                        }}
                    >
                        {"User" if s == "user" else "Workspace"}
                    </button>
                    for s in ["user", "workspace"]
                ]}
                <span style={{"flex": "1"}} />
                <button onClick={lambda (e: any) { onOpenJson(scope); }} style={LINK_STYLE}>{json_label}</button>
            </div>
        </div>
        <div style={{"display": "flex", "flex": "1", "minHeight": "0"}}>
            <div style={{"width": "190px", "flexShrink": "0", "padding": "0.5rem 0 0.5rem 2rem", "fontSize": "13px", "overflow": "auto"}}>
                {[
                    <button
                        key={c["name"]}
                        onClick={lambda (e: any) { category = c["name"] if category != c["name"] else ""; }}
                        style={{
                            "display": "flex", "justifyContent": "space-between", "width": "100%", "background": "none",
                            "border": "none", "padding": "0.25rem 0.5rem", "textAlign": "left", "cursor": "pointer",
                            "color": "#ffffff" if category == c["name"] else "#cccccc",
                            "fontWeight": "600" if category == c["name"] else "400"
                        }}
                    >
                        <span>{c["name"]}</span>
                        <span style={{"opacity": "0.55"}}>{str(c["count"])}</span>
                    </button>
                    for c in categories
                ]}
            </div>
            <div style={{"flex": "1", "overflow": "auto", "padding": "0.5rem 2rem 2rem 1rem"}}>
                {[
                    <div
                        key={spec["key"]}
                        style={{
                            "padding": "0.9rem 0 0.9rem 0.9rem", "position": "relative",
                            "borderLeft": "2px solid #3794ff" if is_modified(spec, scope, user_values, workspace_values) else "2px solid transparent"
                        }}
                    >
                        <div style={{"display": "flex", "alignItems": "baseline", "gap": "0.7rem"}}>
                            <span style={{"fontSize": "13px", "fontWeight": "600", "color": "#e0e0e0"}}>{setting_title(spec)}</span>
                            {(
                                <button onClick={lambda (e: any) { reset(spec["key"]); }} style={LINK_STYLE}>Reset Setting</button>
                            ) if is_modified(spec, scope, user_values, workspace_values) else None}
                        </div>
                        <div style={{"fontSize": "12px", "opacity": "0.7", "margin": "0.25rem 0 0.5rem"}}>{spec["description"]}</div>
                        {(
                            <label style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "fontSize": "13px"}}>
                                <input
                                    type="checkbox"
                                    checked={shown_value(spec, scope, user_values, workspace_values) == True}
                                    onChange={lambda (e: any) { change(spec["key"], e.target.checked); }}
                                />
                                Enabled
                            </label>
                        ) if spec["type"] == "boolean" else (
                            <select
                                value={str(shown_value(spec, scope, user_values, workspace_values))}
                                aria-label={setting_title(spec)}
                                onChange={lambda (e: any) { change(spec["key"], e.target.value); }}
                                style={FIELD_STYLE}
                            >
                                {[<option key={o} value={o}>{o}</option> for o in spec["options"]]}
                            </select>
                        ) if spec["type"] == "enum" else (
                            <input
                                type="number"
                                aria-label={setting_title(spec)}
                                value={drafts[spec["key"]] if spec["key"] in drafts else str(shown_value(spec, scope, user_values, workspace_values))}
                                onChange={lambda (e: any) { edit_draft(spec["key"], e.target.value); }}
                                onBlur={lambda (e: any) { commit_number(spec["key"]); }}
                                onKeyDown={lambda (e: any) { if e.key == "Enter" { commit_number(spec["key"]); } }}
                                style={{**FIELD_STYLE, "width": "9rem"}}
                            />
                        )}
                        {(
                            <div role="alert" style={{"color": "#f48771", "fontSize": "12px", "marginTop": "0.3rem"}}>{errors[spec["key"]]}</div>
                        ) if spec["key"] in errors else None}
                    </div>
                    for spec in shown
                ]}
                {(
                    <div style={{"padding": "1rem 0", "fontSize": "13px", "opacity": "0.6"}}>No settings found.</div>
                ) if len(shown) == 0 else None}
            </div>
        </div>
    </div>
}
