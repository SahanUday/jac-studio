# Research notes: how upstream VS Code is actually built

Source: `/home/sahan/dev/vs/vscode` (microsoft/vscode checkout), investigated 2026-08-22.
This is a grounding reference for [`../architecture.md`](../architecture.md) — not a plan, just facts.

## Scale (measured, not estimated)

```
src/vs/base       154,711 lines /   484 files   — foundation utils, cross-platform abstractions
src/vs/platform   580,107 lines / 2,338 files   — DI infra + platform services
src/vs/editor     279,192 lines /   857 files   — Monaco: text editing engine
src/vs/workbench 1,420,851 lines / 4,039 files  — the whole app shell + all contrib features
src/vs/code         6,236 lines /    19 files   — Electron main-process bootstrap
```

`workbench` alone is ~5x the size of `editor`. Most of what makes VS Code "VS Code" — the
activity bar, panels, settings UI, debug UI, SCM UI, terminal, every built-in feature — lives in
`workbench/contrib/*`, not in the editor core. This is the single biggest sizing signal for
scoping an MVP: the text-editing engine is comparatively small; the workbench chrome is the bulk
of the codebase, and it's built almost entirely out of one repeating pattern (see below), not
bespoke code per feature.

## Layering rule (enforced by `npm run valid-layers-check`)

`base → platform → editor → workbench → code`. Each layer may only depend on layers to its left.
`vs/sessions` sits alongside `workbench` (agent-sessions window) and may import from workbench,
not vice versa. This is the architectural backbone we're mapping onto a Jac equivalent.

- **base**: pure, platform-agnostic utilities (events, lifecycle/disposables, collections, async
  helpers). No services, no DI.
- **platform**: the dependency-injection system itself (`instantiationService`) plus all
  cross-cutting services (configuration, files, storage, telemetry, log, extensions-management).
  Every service is an interface (`IFooService`) + `createDecorator<IFooService>('fooService')` +
  a concrete registered implementation.
- **editor**: Monaco — text model, view, controller, language services. Usable standalone
  outside VS Code (it's shipped as the `monaco-editor` npm package).
- **workbench**: the application itself — parts (activity bar, sidebar, editor groups, panel,
  statusbar), `workbench/services/*` (workbench-level services), `workbench/contrib/*` (every
  built-in feature: git, debug, search, terminal, extensions view, settings UI — each contrib is
  largely self-registering and independent), `workbench/api/*` (the extension host bridge).
- **code**: Electron main-process entry point only. Thin.

## Dependency injection

Confirmed in `src/vs/platform/instantiation/common/instantiation.ts`: constructor-injection via
`createDecorator<IFooService>('fooService')`, consumed as a typed constructor parameter
(`@IFooService private readonly fooService: IFooService`). `IInstantiationService.createInstance`
resolves the graph. Copilot-instructions.md (maintainer-authored) states the hard rule: **service
dependencies must be declared in constructors, never pulled from `IInstantiationService` ad hoc**.
This is VS Code's answer to "how do 4,000+ files share state and behavior without a global
singleton mess" — every service is requested, not reached for.

## Contribution/registry model

The other half of how workbench scales to 4,000 files: features register themselves into global
registries (commands, menus, views, configuration schema) at load time rather than being wired up
imperatively by a central file. A `workbench/contrib/xyz/` folder is largely self-contained:
it defines its own commands/menu entries/views and registers them; nothing else needs to know it
exists. This — DI + self-registering contributions — is the pattern that keeps a million-line UI
layer tractable, and it's the pattern most worth preserving in spirit (not mechanically) in a Jac
rewrite.

## Editor core (Monaco)

`src/vs/editor/common/model/` confirms the classic split:
- `pieceTreeTextBuffer/` — the actual text storage (piece-table over immutable string chunks;
  O(log n) insert/delete/read). Self-contained, algorithmic, minimal external deps — the best
  first candidate for the TS→Jac translator (see [`../translator-strategy.md`](../translator-strategy.md)).
- `textModel.ts` / `textModelPart.ts` — the document model built on top of the buffer (decorations,
  edit stack/undo, search, guides, brackets).
- `intervalTree.ts`, `prefixSumComputer.ts` — supporting pure data structures (decoration lookup,
  line-offset math). Also good translator targets: small, pure, well-unit-tested.
- `tokens/` — tokenization results storage, feeding syntax highlighting.

Model/view/controller separation means the buffer and tokenizer are usable headlessly, which
matters for us: we can port/verify the *algorithms* independent of any rendering surface.

## Extension host

`src/vs/workbench/services/extensions/{common,browser,electron-browser,worker}` +
`src/vs/workbench/api/common/` (extHost*.ts files, e.g. `extHostChatAgents2.ts`,
`extHostAuthentication.ts`, `extHost.protocol.ts`). Extensions run in a **separate process** (or
a web worker in browser/web builds), never in the renderer. Every extension-facing API surface has
a paired `extHostXxx.ts` (runs in extension process) / `mainThreadXxx.ts` (runs in workbench)
split, talking over an RPC protocol (`extHost.protocol.ts` defines the wire contract). This is a
strict trust boundary: the workbench never lets extension code run in its own process/thread.
That boundary is the part we currently have **no equivalent for** in Jac (see gap #5 in
[`jac-capabilities.md`](jac-capabilities.md)) — it's the single riskiest unknown in the whole
reimplementation, not the text editor.

## IPC

`src/vs/base/parts/ipc/common/{ipc.ts, ipc.electron.ts, ipc.mp.ts, ipc.net.ts}` — a small set of
transport-agnostic channel abstractions (`IChannel`/`IServerChannel`) with concrete transports for
Electron IPC, MessagePort, and raw sockets (used for remote/server scenarios). Everything
inter-process (main ↔ renderer ↔ extension host, or workbench ↔ remote server) goes through this
same abstraction with a swappable transport. Conceptually this is exactly what Jac's
walker-spawn-over-RPC already gives us for free between client and server codespaces — see
[`../architecture.md`](../architecture.md) for the mapping.

## Coding conventions worth carrying over in spirit

From `.github/copilot-instructions.md` (maintainer-authored, not inferred):
- Every disposable object is registered for cleanup immediately at creation (`DisposableStore`) —
  no manual "remember to unsubscribe" burden left to reviewers.
- Events are for broadcasting state changes, never for driving control flow between components —
  direct calls are preferred so dependencies stay traceable.
- Storage/state belonging to one component is never touched directly by another; components
  expose an API instead of relying on shared storage keys.
- UI review is done in named-vocabulary design terms (Calm/Focused/Consistent/Delightful →
  principle → token/tier/ramp), not ad hoc pixel pushing.

These aren't VS-Code-specific tricks — they're general large-codebase hygiene, and worth writing
into a `docs/conventions.md` for jac-studio once the project has enough contributors to need one
(tracked in the roadmap, not urgent for MVP).
