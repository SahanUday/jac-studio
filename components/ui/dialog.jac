"""`DialogOverlay`'s dim (`bg-black/10`) and backdrop-blur are removed (2026-09-01) -- this
project's only consumer of `Dialog`/`DialogContent` is `components/ui/command.jac`'s
`CommandDialog` (Command Palette/Quick Open/Task Picker), and real VS Code's own Quick Input
widget doesn't dim the workbench behind it at all -- it floats over a fully visible, undimmed app,
unlike a true modal dialog. `DialogOverlay` element itself stays (Radix's click-outside-to-dismiss
behavior needs it to exist), just visually transparent. `DialogContent` forwards an optional
`overlayClassName` prop to `DialogOverlay` for any future consumer that *does* want a dimmed
overlay -- transparent is the new default, not the only option."""

import from "radix-ui" { Dialog as DialogPrimitive }
import from ...lib.utils { cn }
import from .button { buttonVariants }

def:pub Dialog(props: any) -> JsxElement {
    <DialogPrimitive.Root data-slot="dialog" {**props}/>
}

def:pub DialogTrigger(props: any) -> JsxElement {
    <DialogPrimitive.Trigger data-slot="dialog-trigger" {**props}/>
}

def:pub DialogPortal(props: any) -> JsxElement {
    <DialogPrimitive.Portal data-slot="dialog-portal" {**props}/>
}

def:pub DialogClose(props: any) -> JsxElement {
    <DialogPrimitive.Close data-slot="dialog-close" {**props}/>
}

def:pub DialogOverlay(props: any) -> JsxElement {
    <DialogPrimitive.Overlay
        {**props}
        data-slot="dialog-overlay"
        className={cn(
            "data-open:animate-in data-closed:animate-out data-closed:fade-out-0 data-open:fade-in-0 duration-100 fixed inset-0 isolate z-50",
            props["className"]
        )}
    />
}

def:pub DialogContent(props: any) -> JsxElement {
    showCloseButton = props["showCloseButton"] is not False;
    <DialogPortal>
        <DialogOverlay className={props["overlayClassName"]}/>
        <DialogPrimitive.Content
            {**props}
            data-slot="dialog-content"
            className={cn(
                "bg-background data-open:animate-in data-closed:animate-out data-closed:fade-out-0 data-open:fade-in-0 data-closed:zoom-out-95 data-open:zoom-in-95 ring-foreground/10 grid max-w-[calc(100%-2rem)] gap-4 rounded-xl p-4 text-sm ring-1 duration-100 sm:max-w-sm data-open:animate-in data-closed:animate-out data-closed:fade-out-0 data-open:fade-in-0 data-closed:zoom-out-95 data-open:zoom-in-95 bg-background ring-foreground/10 grid max-w-[calc(100%-2rem)] gap-4 rounded-xl p-4 text-sm ring-1 duration-100 sm:max-w-sm fixed top-1/2 left-1/2 z-50 w-full -translate-x-1/2 -translate-y-1/2 outline-none",
                props["className"]
            )}
        >
            {props["children"]}{showCloseButton
                and <DialogPrimitive.Close data-slot="dialog-close" asChild={True}>
                    <button
                        className={cn(
                            buttonVariants().call(
                                None, {"variant": "ghost", "size": "icon-sm"}
                            ),
                            "absolute top-2 right-2"
                        )}
                    >
                        <span className="codicon codicon-close" style={{"fontSize": "14px"}} />
                        <span className="sr-only">Close</span>
                    </button>
                </DialogPrimitive.Close>}
        </DialogPrimitive.Content>
    </DialogPortal>
}

def:pub DialogHeader(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    <div
        {**attrs}
        data-slot="dialog-header"
        className={cn("gap-2 flex flex-col gap-2", props["className"])}
    />
}

def:pub DialogFooter(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    showCloseButton = props["showCloseButton"] or False;
    <div
        {**attrs}
        data-slot="dialog-footer"
        className={cn(
            "bg-muted/50 -mx-4 -mb-4 rounded-b-xl border-t p-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end",
            props["className"]
        )}
    >
        {props["children"]}{showCloseButton
            and <DialogPrimitive.Close asChild={True}>
                <button
                    className={cn(buttonVariants().call(None, {"variant": "outline"}))}
                >
                    Close
                </button>
            </DialogPrimitive.Close>}
    </div>
}

def:pub DialogTitle(props: any) -> JsxElement {
    <DialogPrimitive.Title
        {**props}
        data-slot="dialog-title"
        className={cn(
            "text-base leading-none font-medium text-base leading-none font-medium", props["className"]
        )}
    />
}

def:pub DialogDescription(props: any) -> JsxElement {
    <DialogPrimitive.Description
        {**props}
        data-slot="dialog-description"
        className={cn(
            "text-muted-foreground *:[a]:hover:text-foreground text-sm *:[a]:underline *:[a]:underline-offset-3 text-muted-foreground text-sm", props["className"]
        )}
    />
}
