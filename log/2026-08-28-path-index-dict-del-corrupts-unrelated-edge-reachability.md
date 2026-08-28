---
id: 2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability
date: 2026-08-28
category: compiler-bug
severity: major
status: workaround
phase: 3
subsystem: workbench-shell
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [persistence, reachability, jac-test, graph, dict]
---

## What happened

Building the file-tree context menu's rename operation (`workspace_service.jac`'s `rename_path`),
a plain Python `del` on one entry of a module-level `glob dict[str, dict[str, T]]` cache
(`_path_index`, this project's established service-registry read cache -- see
`docs/architecture.md`'s service-registry section) corrupted an *entirely unrelated* node's
edge-reachability, isolated with `jac test` by bisecting a minimal repro line-by-line.

## Repro (isolated minimal case)

```jac
node Parent { has name: str; }
node Child { has name: str, path: str; }
edge Contains {}

# This passes:
test "raw traversal after mutating via a jobj-resolved reference" {
    p = root ++> Parent(name="p");
    c = Child(name="a.txt", path="/tmp/a.txt");
    p +>:Contains():+> c;
    resolved = jobj(jid(c)) as Child;
    resolved.name = "renamed.txt";
    children = [p->:Contains:->];
    assert "renamed.txt" in [x.name for x in children];  # passes
}
```

That much is fine. The actual break needed the real `workspace_service.jac` shape: a module-level
`glob _path_index: dict[str, dict[str, T]]` caching node references for reads, plus a rename
function that (a) resolves a cached reference via `jobj(jid(cached))`, (b) mutates its fields, (c)
then does `del _path_index[key][old_path]; _path_index[key][new_path] = fresh;` to re-key the
cache. Bisected line-by-line against a version copied verbatim into the test file itself (ruling
out any cross-module effect):

- With `os.rename(...)`, the `jobj`-then-mutate, and `_path_index[key][new_path] = fresh` (no
  `del`) all present: a subsequent `[parent-->]` traversal from the **unrelated parent** node
  (`Workspace`, holding a *different*, never-touched `Contains` edge to this same child) correctly
  returns `['renamed.txt']`.
- Adding **only** `del _path_index[key][old_path];` before the reassignment: the exact same
  traversal from the exact same parent reference returns `[]` -- completely empty. The parent's
  own edge to the renamed child appears to have vanished, even though nothing in the diff touched
  that edge or that parent node at all.

Confirmed via `cached_parent is fresh_parent` (both `True`, same identity) that this isn't a
stale-object-copy issue -- both a cached reference and a fresh `jobj()` resolve of the identical
jid returned the corrupted (empty) result.

## Why this looks like a reachability bug, not a dict bug

The `del` is on a **plain Python dict** (`_path_index`), not a graph mutation of any kind -- it has
no business affecting a `Contains` edge between two node objects it doesn't even reference by that
point (only the *child* end was ever in that dict entry, never the *parent*). The most plausible
mechanism, not traced further into the runtime: jaseci's "persistence by reachability" model
(`docs/architecture.md`'s own description of the graph-as-service-registry pattern) appears to
treat in-process references -- including ones sitting in an ordinary application-level dict, not
just graph edges -- as inputs to some reachability computation, and dropping the *last* such
reference to a node while it still holds a live edge elsewhere triggers an over-eager detach that
also takes out that unrelated edge.

## Why `delete_path` (immediately next to this code) doesn't hit it

`delete_path` also does `del _path_index[key][path]`, and works correctly -- the same bisection
confirmed the difference: `delete_path` explicitly detaches all of the node's own edges (`del e` on
both `[edge node ->:Contains:->]` and `<-:Contains:<-]`) **before** the dict `del`. A node with zero
edges has nothing left to spuriously corrupt. `rename_path`'s node, at the point of its `del`, still
had a live edge (deliberately -- the whole point of a rename is keeping the file "in place" in the
tree).

## Plan

Workaround shipped in `rename_path`: never `del` the stale `old_path` key out of `_path_index` at
all -- just leave it pointing at the (now-renamed, or in the current code, fully replaced) object.
Harmless: nothing will ever legitimately look up a path that no longer exists on disk. This is a
narrower, silent trap that could resurface anywhere else in this project (or any jac-studio-style
app) that mixes a plain in-process cache dict with graph mutations across nodes that share edges --
worth a real fix or at least a documented gotcha upstream, since "don't `del` a dict key holding a
still-graph-attached node reference" is not discoverable without exactly this kind of bisection.
