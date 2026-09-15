"""WorkspaceWatcher: a general, OS-level (`watchdog`) file-change notifier for the open workspace,
polled from the client -- never a push (ADR 0071 covers why: an earlier SSE-streamed version broke
`list_children_by_path` server-wide). Watches are scheduled per directory, non-recursively,
excluding `DEFAULT_EXCLUDED_DIRS`, and swapped whenever a different workspace opens. Directory
events use an explicit allowlist, not a blocklist -- `watchdog` emits more event types than the
four this module handles. See `docs/known-limitations.md` for the delete/recreate race this
doesn't cover."""

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

# Runs on watchdog's own background thread -- every access to the globals above goes through
# _watch_lock, same convention as workspace_service.jac's _workspace_lock.
#
# A directory's own `modified` event is noise, not signal: creating a file inside a directory
# changes that directory's mtime too, and dirname() of a directory's own path is its parent, one
# level too high. created/deleted/moved already mark the right directory via the file's own event.
# A file's `modified` event IS real signal (_modified_files), for an already-open tab whose content
# changed on disk. Both branches use an explicit allowlist, not a `!= "modified"` blocklist --
# watchdog also emits opened/closed/closed_no_write, which a blocklist would let through as noise.
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
