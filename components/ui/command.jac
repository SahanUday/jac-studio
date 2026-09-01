"""Restyled to VS Code's own dark Quick Input widget palette (2026-09-01, `docs/roadmap.md`
Phase 4), not the shadcn `bg-popover`/`bg-background` CSS-variable tokens `jac install --shadcn
command` originally generated. Same root cause `activity_bar.jac`'s own docstring already
documents for this project's other hand-styled workbench-shell pieces: this project's theme
toggle doesn't reach the shadcn-primitive-driven chrome the way it reaches everything else, so
`Command`/`CommandDialog` rendered with the *light* default palette regardless of the app's own
otherwise-dark chrome -- confirmed live via screenshot, not assumed. Hardcoded hex, matching the
exact convention `file_tree.jac`/`activity_bar.jac`/`editor_tabs.jac` already use for the identical
reason, rather than fixing the underlying CSS-variable gap here (that's real, cross-cutting work
for all of these components together in one pass, out of scope for a two-component visual parity
pass). Colors are VS Code's own Dark+ Quick Input widget values (`editorWidget.background`
`#252526`, `widget.border` `#454545`), not invented -- the whole point of this pass is visual
parity with the real thing, not a fresh palette.

**Every consumer (`command_palette.jac`, `quick_open.jac`, `task_picker.jac`) shares this one
file** -- restyling once here, rather than three times at each call site, and keeping them
visually consistent with each other for free, the same reasoning that already justified centralizing
these primitives in the first place.

**No fuzzy-match character highlighting (deliberate scope cut, not an oversight).** Real VS Code
bolds/colors the matched characters within each result label. The underlying `cmdk` npm package's
`filter` prop only returns a numeric rank score, not match *positions* -- getting per-character
highlight spans would mean swapping in a separate fuzzy-match library with position tracking, a
real, separate follow-up, not a styling change. Keyboard navigation (arrows/Enter/Escape) and
substring filtering both already come free from `cmdk` itself, unaffected by this restyle.

**`CommandInput`'s `prefix` prop is new** -- an optional literal character rendered before the
input box, for `command_palette.jac` to pass `">"` the same way real VS Code visually distinguishes
"this is the Command Palette" from Quick Open's plain input (which passes no prefix)."""

import from "cmdk" { Command as CommandPrimitive }
import from .dialog {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle
}
import from ...lib.utils { cn }

glob _QUICK_INPUT_BG: str = "#252526";
glob _QUICK_INPUT_BORDER: str = "#454545";
glob _QUICK_INPUT_TEXT: str = "#CCCCCC";
glob _QUICK_INPUT_MUTED: str = "#8C8C8C";
glob _QUICK_INPUT_SELECTED_BG: str = "#04395E";
glob _QUICK_INPUT_KEYBINDING_BG: str = "#3A3D41";

def:pub Command(props: any) -> JsxElement {
    <CommandPrimitive
        data-slot="command"
        {**props}
        className={cn("rounded-md! p-1 flex size-full flex-col overflow-hidden", props["className"])}
        style={{"background": _QUICK_INPUT_BG, "color": _QUICK_INPUT_TEXT}}
    />
}

def:pub CommandDialog(props: any) -> JsxElement {
    title = props["title"] or "Command Palette";
    description = props["description"] or "Search for a command to run...";
    showCloseButton = props["showCloseButton"] or False;
    <Dialog {**props}>
        <DialogHeader className="sr-only">
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <DialogContent
            {**props}
            className={cn(
                "rounded-md! top-1/4 translate-y-0 overflow-hidden p-0 border sm:max-w-2xl ring-0! shadow-2xl",
                props["className"]
            )}
            style={{"background": _QUICK_INPUT_BG, "borderColor": _QUICK_INPUT_BORDER}}
            showCloseButton={showCloseButton}
        >
            <Command className="[&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group]]:px-2 [&_[cmdk-group]:not([hidden])_~[cmdk-group]]:pt-0 [&_[cmdk-item]]:px-3 [&_[cmdk-item]]:py-1.5">
                {props["children"]}
            </Command>
        </DialogContent>
    </Dialog>
}

def:pub CommandInput(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    prefix = attrs.pop("prefix", "");
    <div
        data-slot="command-input-wrapper"
        style={{"display": "flex", "alignItems": "center", "gap": "0.5rem", "padding": "0.6rem 0.75rem", "borderBottom": "1px solid " + _QUICK_INPUT_BORDER}}
    >
        {(<span style={{"color": _QUICK_INPUT_TEXT, "fontSize": "13px", "flexShrink": "0"}}>{prefix}</span>) if prefix != "" else None}
        <CommandPrimitive.Input
            data-slot="command-input"
            {**attrs}
            className={cn("w-full text-sm outline-hidden disabled:cursor-not-allowed disabled:opacity-50", attrs["className"])}
            style={{"background": "transparent", "border": "none", "color": _QUICK_INPUT_TEXT}}
        />
    </div>
}

def:pub CommandList(props: any) -> JsxElement {
    <CommandPrimitive.List
        data-slot="command-list"
        {**props}
        className={cn(
            "no-scrollbar max-h-96 scroll-py-1 outline-none overflow-x-hidden overflow-y-auto", props["className"]
        )}
    />
}

def:pub CommandEmpty(props: any) -> JsxElement {
    <CommandPrimitive.Empty
        data-slot="command-empty"
        {**props}
        className={cn("py-6 text-center text-sm", props["className"])}
        style={{"color": _QUICK_INPUT_MUTED}}
    />
}

def:pub CommandGroup(props: any) -> JsxElement {
    <CommandPrimitive.Group
        data-slot="command-group"
        {**props}
        className={cn("overflow-hidden p-1 **:[[cmdk-group-heading]]:py-1.5 **:[[cmdk-group-heading]]:text-xs **:[[cmdk-group-heading]]:font-medium **:[[cmdk-group-heading]]:uppercase **:[[cmdk-group-heading]]:tracking-wide", props["className"])}
        style={{"color": _QUICK_INPUT_TEXT}}
    />
}

def:pub CommandSeparator(props: any) -> JsxElement {
    <CommandPrimitive.Separator
        data-slot="command-separator"
        {**props}
        className={cn("-mx-1 h-px", props["className"])}
        style={{"background": _QUICK_INPUT_BORDER}}
    />
}

def:pub CommandItem(props: any) -> JsxElement {
    <CommandPrimitive.Item
        data-slot="command-item"
        {**props}
        className={cn(
            "relative flex cursor-default items-center gap-2 rounded-sm text-sm outline-hidden select-none [&_svg:not([class*='size-'])]:size-4 group/command-item data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50 data-selected:[background-color:#04395E]",
            props["className"]
        )}
    >
        {props["children"]}
    </CommandPrimitive.Item>
}

def:pub CommandShortcut(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    <span
        data-slot="command-shortcut"
        {**attrs}
        className={cn("ml-auto text-xs tracking-wide rounded-sm", attrs["className"])}
        style={{"color": _QUICK_INPUT_TEXT, "background": _QUICK_INPUT_KEYBINDING_BG, "padding": "1px 5px", "border": "1px solid " + _QUICK_INPUT_BORDER}}
    />
}
