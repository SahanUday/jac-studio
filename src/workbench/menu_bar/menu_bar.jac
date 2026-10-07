"""The title bar's File/Edit/Selection/View/Go/Run/Terminal/Help menus, on shadcn's Radix `Menubar`
(hover-to-switch, arrow keys, type-ahead). Content comes from `menu_model.jac`; a click only calls
`onCommand`, so dispatch stays in `workbench.jac`. Items needing a folder or an editor are disabled
rather than hidden, as in VS Code."""

import from components.ui.menubar {
    Menubar, MenubarMenu, MenubarTrigger, MenubarContent, MenubarItem, MenubarSeparator, MenubarShortcut
}
import from src.workbench.commands.keybinding_label { format_keybinding }
import from src.workbench.menu_bar.menu_model { MENUS, item_enabled, item_shortcut }

glob TRIGGER_STYLE: dict[str, str] = {
    "fontSize": "12px", "fontWeight": "400", "color": "#cccccc", "padding": "0.15rem 0.55rem", "borderRadius": "4px"
};

"""A lambda written inside the item loop would share one hoisted `command_id`, so every item would run
the last one's command; binding through a call gives each its own."""
def _select_handler(on_command: any, command_id: str) -> any {
    return lambda (e: any) { on_command(command_id); };
}

def:pub app(commands: list[dict[str, any]], hasWorkspace: bool, hasTab: bool, hasEditor: bool, onCommand: any) -> JsxElement {
    labels = {c["id"]: format_keybinding(c["keybindings"]) for c in commands};
    menu_nodes = [];
    for menu in MENUS {
        item_nodes = [];
        items = menu["items"];
        for idx in range(len(items)) {
            item = items[idx];
            if item.get("separator") {
                item_nodes.append(<MenubarSeparator key={"sep-" + str(idx)} />);
                continue;
            }
            command_id = item["command"];
            item_nodes.append(
                <MenubarItem
                    key={command_id + ":" + str(idx)}
                    disabled={not item_enabled(item, hasWorkspace, hasTab, hasEditor)}
                    onSelect={_select_handler(onCommand, command_id)}
                    style={{"fontSize": "13px"}}
                >
                    {item["label"]}
                    <MenubarShortcut>{item_shortcut(item, labels.get(command_id, ""))}</MenubarShortcut>
                </MenubarItem>
            );
        }
        menu_nodes.append(
            <MenubarMenu key={menu["label"]}>
                <MenubarTrigger style={TRIGGER_STYLE}>{menu["label"]}</MenubarTrigger>
                <MenubarContent className="dark" style={{"minWidth": "240px"}}>{item_nodes}</MenubarContent>
            </MenubarMenu>
        );
    }

    <Menubar style={{"height": "100%", "border": "none", "background": "transparent", "padding": "0", "gap": "0"}}>
        {menu_nodes}
    </Menubar>
}
