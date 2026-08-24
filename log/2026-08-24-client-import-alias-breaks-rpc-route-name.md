---
id: 2026-08-24-client-import-alias-breaks-rpc-route-name
date: 2026-08-24
category: compiler-bug
severity: minor
status: workaround
phase: 2
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, client, rpc, imports]
---

## What we tried

The file-tree sidebar's client component (`src/workbench/file_tree/file_tree.jac`) needed to call
a server function also named `open_workspace`, while the client's own instance method was, at
first, also going to be named `open_workspace` -- a naming collision. Followed the standard
import-alias escape hatch already used elsewhere in this project for npm imports (e.g. `import
from "radix-ui" { ScrollArea as ScrollAreaPrimitive }` in the vendored shadcn `scroll_area.jac`):

```jac
import from src.workbench.workspace.workspace_service { open_workspace as server_open_workspace, ... }
```

## What happened

`jac check` and `jac test` both passed. The compiled client bundle, however, showed the RPC call
still targeting the *original* server-side name as a string, called through the *aliased* local
binding:

```js
result = await __jacCallFunction("server_open_workspace", {"root_path": path});
```

Confirmed by reading `client_runtime_core.impl.jac`: `__jacCallFunction(function_name, args)`
issues `POST {api_base}/function/{function_name}` -- the route path is the literal string handed
to it by the caller, and `jac2js` bakes in the *local identifier* the aliased import bound
(`server_open_workspace`), not the real exported name the server actually registers a route under
(`open_workspace`). This would 404 at runtime (confirmed the server registers under the real name:
`curl -X POST http://localhost:5184/function/open_workspace` succeeds; the aliased name is never a
valid route). Neither `jac check` nor `jac test` catch this -- both are server/static-side and
never exercise the compiled bundle's route-name strings; only an actual `jac dev` session plus a
real RPC call (or a browser click) surfaces it.

**Workaround** (in place now): don't alias a client-facing `def:pub` import at all. Renamed the
*client's own* colliding method instead (`app.open_workspace` -> `app.open_folder`), keeping the
imported server function under its real name.

## Plan

Not filing upstream yet -- the mechanism is plausible as scoped `jac2js` behavior (it likely
resolves the RPC target from the import's local binding name rather than tracing back to the
aliased symbol's original declaration), and the workaround costs nothing. Worth a minimal repro
upstream if a case comes up where renaming the caller's own identifier isn't a clean option (e.g.
two same-named server functions genuinely needing to be called side by side from one client
file, which would force aliasing). General guidance: never alias a client-side import of a
`def:pub` server function; rename the local caller instead when a collision would otherwise
require it.
