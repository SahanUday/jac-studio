"""WorkspaceWatcher: a general, feature-agnostic external-file-change notifier for the currently
open workspace -- closes a real gap found live (2026-09-04, real-user QA): a file the AI agent's
own `Write` tool created was genuinely on disk but never appeared in `file_tree.jac`'s Explorer
tree, since nothing in this project's client-side state had any way to know a write happened
outside its own RPC calls.

**A first fix wired a dedicated `onWorkspaceFileChanged` callback directly from `ai_chat.jac`'s own
`tool_result` handling -- correct, but special-cased to one specific *cause* of an external change
(this app's own AI tool calls), not the general problem.** Asked to check how real VS Code handles
this, and it doesn't special-case causes either: `IFileService.onDidFilesChange`
(`explorerService.ts` in a real `microsoft/vscode` checkout) is one general, OS-level file-system
watcher covering the *entire* open workspace, feeding a single event stream that the Explorer (and
everything else that cares) subscribes to, regardless of whether a change came from an AI tool, a
terminal command, `git checkout`, or another program entirely.

**A second, real, live-reproduced regression, same day: an indefinite SSE stream
(`watch_workspace_changes() -> Generator`) broke `list_children_by_path` server-wide the moment it
started running** -- this project's own already-documented SSE-generator-isolation risk (see
`claude_code_client.jac`'s docstring and tracker entries
`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`/
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`/
`2026-09-05-sse-generator-root-scoped-graph-query-unreliable`), worse here because every other
`Generator` in this codebase was short-lived and this one never disconnected. **Fixed, same day, by
replacing the stream with a stateless polled function** (`check_workspace_changes(root_path,
last_snapshot)`, an ordinary `def:pub` the client called on a `setInterval`) that did a fresh
`os.walk` of the whole tree and diffed it against whatever snapshot the client sent back -- correct
and safe (no stream, no isolation risk), but exactly the polling-and-diffing shape a user later
flagged as wasteful: **a full recursive directory walk every second, forever, regardless of whether
anything changed** (2026-09-04, same-day follow-up QA) -- real, measurable CPU cost on a big tree
for a signal that's usually "nothing happened." Asked again to check how VS Code's own production
architecture handles this specific tradeoff.

**It doesn't poll at all.** `IFileService`'s watcher is backed by a real OS-level notification
mechanism (inotify on Linux, equivalent APIs elsewhere) -- the OS tells the process when something
changed; nothing walks the tree on a timer to find out. `files.watcherExclude`
(`node_modules/**`, `.git/objects/**`, ...) prunes exactly what this project's own
`DEFAULT_EXCLUDED_DIRS` already prunes from `os.walk`, and for the identical reason: a huge
`node_modules` tree (this project's own frontend has one) would otherwise burn OS watch handles and
wake the process for churn nobody's watching.

**This module now does the same, using `watchdog` (added as a new dependency, `jac.toml`) --
confirmed live, not assumed, that this is safe to add:** unlike `claude_agent_sdk` (whose huge
transitive dependency closure is documented, see
`2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure`, to blow up
jaclang's own compiler at `.jac` module scope), a real `jac check` against a probe file importing
`watchdog.observers.Observer`/`watchdog.events.FileSystemEventHandler` at module scope, and a real
`jac run` of a script that subclasses `FileSystemEventHandler` as a Jac `obj`, schedules a real
`Observer` against a real directory, writes a file into it, and confirms the overridden
`on_any_event` actually fires (virtual dispatch across the Jac/Python boundary, not just an import),
both passed clean -- this dependency is small enough, and Jac's single-inheritance `obj X(PyClass)`
support real enough, to build this the way a native desktop app would.

**Watches are scheduled per-directory, non-recursively, exactly mirroring `files.watcherExclude`'s
own reasoning** -- `watchdog.Observer.schedule(..., recursive=True)` on the workspace root would
place an inotify watch on *every* subdirectory including `node_modules`/`.git`, defeating the whole
point. Instead, `_start_watch_locked` walks the tree once at watch-start (reusing the same
`DEFAULT_EXCLUDED_DIRS` filter `workspace_service.jac`'s own `os.walk` calls already use) and
schedules each non-excluded directory individually; a `created` event for a new, non-excluded
directory schedules that directory too, so a freshly-created subtree keeps being watched without a
full re-scan. One process-wide watch at a time, swapped (old `Observer` stopped, new one started)
whenever `_open_path_into_tree` opens a different root -- this app only ever has one workspace open,
so there is never more than one OS-level watch to keep alive or leak.

**State moved fully server-side, which is why `check_workspace_changes` dropped its `last_snapshot`
parameter and `snapshot` return value.** The client no longer carries a `watch_snapshot` field at
all (see `file_tree.jac`) -- it just polls `check_workspace_changes(root_path)` on a
`setInterval` (still an ordinary, non-`Generator` `def:pub` call, so none of the SSE-isolation risk
above applies) and gets back whichever directories the OS actually reported changed since the last
poll, drained from a small in-memory set `_dirty_dirs` that the watcher's own background thread
fills and the poll handler empties under `_watch_lock`. The poll transport itself is unchanged and
still deliberately not a push (a truly zero-latency push would mean going back to a live connection
per client, reopening the exact isolation risk this module was rewritten once already to avoid);
what changed is that answering a poll is now an O(1) dict/set read instead of an O(files) disk walk
-- the OS did the expensive part once, continuously, in the background, the way a real file watcher
is supposed to.

**Still directory-granularity, not per-file** -- an event's *containing* directory (`dirname` of
`src_path`, and of `dest_path` too for a `moved` event, since an item can move between two different
visible directories) is what's marked dirty, matching what the client actually needs
(`file_tree.jac`'s `poll_workspace_changes` only calls `refresh_children` for directories it has
already loaded). A deleted subdirectory is still caught correctly: it stops appearing in its own
*parent's* listing, which the parent's own dirty-marking already covers.

**Known, accepted gap, stated honestly rather than papered over:** if a directory is deleted and a
new directory is created at the *exact same path* while a watch is active, the recreated directory
is scheduled again correctly (the `created` handler doesn't check history, only current existence),
but if the delete/recreate happens fast enough that no `deleted`+`created` pair is observed
distinctly (a `moved`/rename in place, or two events coalesced), the freshly-recreated directory's
own *contents* may not get their own individual watches until the next full workspace reopen. This
is a genuinely rare edge case (not exercised by any real QA finding so far, unlike everything else
in this docstring), and the cost of missing it is a stale nested subtree until reopen, not a crash
or wrong data -- not worth the extra bookkeeping a fully defensive version would need until it's a
real, reproduced problem."""

import os;
import threading;
import from watchdog.observers { Observer }
import from watchdog.events { FileSystemEventHandler }
import from src.workbench.workspace.workspace_service { DEFAULT_EXCLUDED_DIRS }

glob _watch_lock: threading.Lock = threading.Lock();
glob _watched_root: str = "";
glob _dirty_dirs: set[str] = set();
glob _modified_files: set[str] = set();
glob _observer: any = None;
glob _scheduled_dirs: set[str] = set();

"""Runs on `watchdog`'s own background OS-notification thread, never on a request-handling one --
every access to the shared globals above goes through `_watch_lock`, the same convention
`workspace_service.jac`'s `_workspace_lock` already establishes for cross-thread access in this
codebase.

**A `modified` event on a *directory* is ignored outright -- confirmed live this is correct, not an
oversight.** A first version handled every event type uniformly (`dirname(event.src_path)`) and,
live-tested against a real create inside `testing-workspace/src/`, wrongly marked the *workspace
root* dirty too: creating a file inside a directory makes that directory's own mtime change, which
`watchdog` separately reports as a `modified` event *on the directory itself*
(`src_path=".../src"`, `is_directory=True`) -- `dirname` of a directory's own path is its *parent*,
not itself, so this seemingly-generic handling silently computed the wrong level one directory
name too high. Since `created`/`deleted`/`moved` already mark the correct directory via the
*file's own* event (whose `dirname` is genuinely its containing directory), and `_dirty_dirs` only
ever cares about the *set of names* in a directory changing (matching the old `os.walk`-diffing
version's own `sorted(dirnames + filenames)` semantics, never file content), a directory-level
`modified` event carries no signal `_dirty_dirs` needs at all.

**A `modified` event on a *file*, though, is now real signal -- `_modified_files` (2026-09-04,
real-user QA), not dropped.** Added for a second consumer this module didn't originally serve: an
already-*open* editor tab whose file changed on disk out from under it (an AI tool write being the
concrete, live-reported case) had no way to know its own displayed content was now stale --
`_dirty_dirs` alone can't answer "did *this specific open file's own content* change," only "did
some directory's *listing* change," and a file being overwritten in place never touches its
parent's listing at all. `on_any_event` now branches on file vs. directory *before* deciding
whether an event is signal or noise, rather than one blanket `event_type == "modified"` check for
everything.

**The directory branch is an explicit allowlist (`in ["created", "deleted", "moved"]`), not a
`!= "modified"` blocklist -- a second real bug caught live while verifying the file-level tracking
above, not by inspection.** Instrumenting this handler directly against a real served `jac run
--dev` process (not the earlier `jac run --no-serve` script probes, which never happened to surface
this) showed `watchdog` emitting `opened`/`closed`/`closed_no_write` events too, in addition to the
four this module was originally built against (`created`/`deleted`/`modified`/`moved`) -- a real,
newly-confirmed fact about this installed `watchdog` version's actual event coverage, not assumed
from its docs. The blocklist form only ever excluded `"modified"`, so any of these three new types
on a *directory* (e.g. simply listing one, which does not change what it contains) would have fallen
through to the unconditional `_dirty_dirs.add(...)` below it, marking that directory's *parent*
spuriously dirty for no real change at all. The file branch already used the correct allowlist shape
for its own `_dirty_dirs` marking (`in ["created", "deleted", "moved"]`); the directory branch now
matches it exactly, closing the same class of gap in the one place it was still open. `opened`/
`closed`/`closed_no_write` need no explicit handling of their own here -- they carry no signal
either `_dirty_dirs` or `_modified_files` needs, on a file or a directory, and now correctly fall
through as pure no-ops on both branches rather than being handled by accident via exclusion."""
obj _DirtyDirHandler(FileSystemEventHandler) {
    def on_any_event(event: any) {
        if event.is_directory {
            if event.event_type not in ["created", "deleted", "moved"] {
                return;
            }
            with _watch_lock {
                dirs_to_mark = [os.path.dirname(event.src_path)];
                if event.event_type == "moved" {
                    dirs_to_mark.append(os.path.dirname(event.dest_path));
                }
                for d in dirs_to_mark {
                    _dirty_dirs.add(d);
                }
                if event.event_type == "created" {
                    _schedule_dir_locked(event.src_path);
                }
            }
            return;
        }
        with _watch_lock {
            if event.event_type in ["created", "deleted", "moved"] {
                dirs_to_mark = [os.path.dirname(event.src_path)];
                if event.event_type == "moved" {
                    dirs_to_mark.append(os.path.dirname(event.dest_path));
                }
                for d in dirs_to_mark {
                    _dirty_dirs.add(d);
                }
            }
            if event.event_type == "modified" {
                _modified_files.add(event.src_path);
            } elif event.event_type == "moved" {
                _modified_files.add(event.dest_path);
            }
        }
    }
}

"""Caller must already hold `_watch_lock`. Schedules exactly one directory, non-recursively, if it
still exists, isn't already scheduled, and isn't one of `DEFAULT_EXCLUDED_DIRS` -- the building
block both the initial full-tree walk and a live `created`-directory event reuse."""
def _schedule_dir_locked(dir_path: str) -> None {
    if dir_path in _scheduled_dirs or os.path.basename(dir_path) in DEFAULT_EXCLUDED_DIRS {
        return;
    }
    if not os.path.isdir(dir_path) {
        return;
    }
    _observer.schedule(_DirtyDirHandler(), dir_path, recursive=False);
    _scheduled_dirs.add(dir_path);
}

"""Caller must already hold `_watch_lock`."""
def _stop_watch_locked {
    if _observer is not None {
        _observer.stop();
        _observer.join(timeout=2.0);
    }
    _observer = None;
    _watched_root = "";
    _dirty_dirs.clear();
    _modified_files.clear();
    _scheduled_dirs.clear();
}

"""Caller must already hold `_watch_lock`. No-op (leaves nothing watched) if `root_path` doesn't
exist -- mirrors `check_workspace_changes`'s old not-a-dir guard."""
def _start_watch_locked(root_path: str) -> None {
    if not os.path.isdir(root_path) {
        return;
    }
    _observer = Observer();
    for (dirpath, dirnames, filenames) in os.walk(root_path) {
        dirnames[:] = [d for d in dirnames if d not in DEFAULT_EXCLUDED_DIRS];
        _schedule_dir_locked(dirpath);
    }
    _observer.start();
    _watched_root = root_path;
}

"""Called once, from `file_tree.jac`'s `_open_path_into_tree`, whenever a workspace opens -- swaps
the single process-wide watch over to `root_path`, a no-op if it's already watching that exact
root. This app only ever has one workspace open at a time, so there is never more than one `Observer`
thread alive."""
def:pub start_or_switch_watch(root_path: str) -> None {
    with _watch_lock {
        if _watched_root == root_path and _observer is not None {
            return;
        }
        _stop_watch_locked();
        _start_watch_locked(root_path);
    }
}

"""One poll tick's worth of work: drains and returns whichever directories changed (`changed_dirs`,
for the Explorer tree -- names added/removed from a directory's own listing) and whichever *files'*
own content changed in place (`changed_files`, for reloading an already-open editor tab -- 2026-09-04,
real-user QA) since the last call, for the workspace currently being watched. Returns no changes
(rather than erroring) if `root_path` doesn't match what's currently watched -- a stale poll from a
workspace that's since been switched away from, which `file_tree.jac`'s own
`useEffect([root_path])` cleanup already guards against in the common case, but a request already in
flight when a switch happens could still land here after the fact."""
def:pub check_workspace_changes(root_path: str) -> dict[str, any] {
    with _watch_lock {
        if _watched_root != root_path {
            return {"changed_dirs": [], "changed_files": []};
        }
        changed = list(_dirty_dirs);
        _dirty_dirs.clear();
        changed_files = list(_modified_files);
        _modified_files.clear();
        return {"changed_dirs": changed, "changed_files": changed_files};
    }
}
