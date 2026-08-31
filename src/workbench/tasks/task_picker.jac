"""TaskPicker: the "Tasks: Run Task" flow (`docs/roadmap.md` Phase 4) -- a second `CommandDialog`
picker, mirroring `command_palette.jac`'s exact shape (fetch a list on mount, `onSelect` reports the
picked item up, the parent owns what running it actually means) rather than teaching the command
palette itself about a second, differently-shaped data source.

**Reads `list_tasks()` fresh every time it opens, not once on first mount** -- unlike
`command_palette.jac`'s `commands` (a fixed, build-time-registered list that never changes within a
session), `.jac-studio/tasks.json` is a plain file a user can hand-edit at any time; showing a stale
list from whenever this component first mounted would be actively wrong, not just imprecise. Reruns
`list_tasks()` on every `open` transition to `True` via `useEffect([open])`, the same "refetch on
becoming visible" pattern `scm.jac` already established for the identical class of problem (see its
own docstring for why a plain `can with entry` isn't enough for state that can go stale after
mount).

**No default keybinding, matching real VS Code's own "Tasks: Run Task" command** -- only "Run Build
Task" (`Ctrl+Shift+B`, a different, narrower command that auto-picks a single build-group task) has
one out of the box; the generic picker is reachable through the Command Palette only. Not
overclaiming a shortcut this project doesn't actually give special build-task-group treatment to.

**Running a task is fire-and-forget from this component's own perspective** -- `onRunTask` (really
`workbench.jac`'s `run_selected_task`) is called and the dialog closes immediately, the same
"select, then let the parent do the slow part" shape `command_palette.jac`'s `handle_select`
already uses; nothing here awaits the task's own completion or blocks the dialog closing on it."""

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
