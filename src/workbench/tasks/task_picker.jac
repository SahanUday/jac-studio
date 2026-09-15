"""The "Tasks: Run Task" picker, a `CommandDialog` mirroring `command_palette.jac`'s shape.
Rereads `list_tasks()` on every `open` transition, not once at mount, since
`.jac-studio/tasks.json` is a plain file a user can hand-edit at any time.
`onRunTask` fires and the dialog closes immediately; nothing here awaits task completion.
"""

import from "react" { useEffect }
import from src.workbench.tasks.task_service { list_tasks }
import from components.ui.command {
    CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem
}

def:pub app(open: bool, onOpenChange: any, onRunTask: any) -> JsxElement {
    has tasks: list[dict[str, any]] = [];

    async def refresh_tasks -> None;
    def handle_select(label: str) -> None;

    useEffect(lambda {
        if open {
            refresh_tasks();
        }
    }, [open]);

    <CommandDialog open={open} onOpenChange={onOpenChange}>
        <CommandInput placeholder="Run a task..." />
        <CommandList>
            <CommandEmpty>
                No tasks configured. Create .jac-studio/tasks.json in your workspace root.
            </CommandEmpty>
            <CommandGroup heading="Tasks">
                {[
                    <CommandItem key={t["label"]} value={t["label"]} onSelect={handle_select}>
                        {t["label"]}
                    </CommandItem>
                    for t in tasks
                ]}
            </CommandGroup>
        </CommandList>
    </CommandDialog>
}
