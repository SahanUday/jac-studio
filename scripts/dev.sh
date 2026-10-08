#!/usr/bin/env bash
# One-command local dev startup: full clean, prune orphaned embedded-Postgres databases
# (jac db prune never touches a project that still exists on disk), install dependencies, serve.
#
#   scripts/dev.sh                    clean start, your real user config
#   scripts/dev.sh --keep             skip the clean, so the saved session survives (persistence tests)
#   scripts/dev.sh --sandbox          isolated user config + a throwaway copy of testing-workspace
#   scripts/dev.sh --terminal         enable [terminal] in jac.toml for this run only
#   scripts/dev.sh --manual           --sandbox --terminal
set -euo pipefail

KEEP=0 SANDBOX=0 TERMINAL=0
for arg in "$@"; do
    case "$arg" in
        --keep) KEEP=1 ;;
        --sandbox) SANDBOX=1 ;;
        --terminal) TERMINAL=1 ;;
        --manual) SANDBOX=1 TERMINAL=1 ;;
        -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$PWD"
BOX="$HOME/.claude-scratch/manual-test"

if [ "$TERMINAL" = 1 ]; then
    if ! git diff --quiet -- jac.toml; then
        echo "jac.toml has uncommitted changes; commit or stash them before using --terminal" >&2
        exit 1
    fi
    trap 'git -C "$ROOT" checkout -- jac.toml' EXIT
    trap 'exit 130' INT TERM
    sed -i '/^\[terminal\]/,/^\[/ s/^enabled = false/enabled = true/' jac.toml
    echo "==> [terminal] enabled for this run (jac.toml is restored on exit)"
fi

if [ "$SANDBOX" = 1 ]; then
    mkdir -p "$BOX"
    if [ "$KEEP" = 0 ]; then
        rm -rf "$BOX/config" "$BOX/workspace"
    fi
    mkdir -p "$BOX/config"
    if [ ! -d "$BOX/workspace" ]; then
        cp -a testing-workspace "$BOX/workspace"
    fi
    export JAC_STUDIO_CONFIG_DIR="$BOX/config"
    echo "==> Sandbox: user config  $BOX/config"
    echo "             workspace    $BOX/workspace  (open this folder in the app)"
fi

echo "==> Clearing any stale process on ports 8000/8001"
for port in 8000 8001; do
    pid="$(lsof -ti ":${port}" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        echo "    killing stale process on :${port} (pid ${pid})"
        kill -9 $pid 2>/dev/null || true
    fi
done

if [ "$KEEP" = 0 ]; then
    echo "==> Cleaning stale .jac build artifacts (data, cache, packages, client)"
    jac clean --all --force

    echo "==> Pruning orphaned databases from the shared embedded Postgres cluster"
    jac db prune -y
fi

echo "==> Installing dependencies"
jac install

echo "==> Starting jac-studio on http://localhost:8000 (Ctrl+C to stop)"
if command -v capped >/dev/null 2>&1; then
    capped --mem 4G -- jac run --dev
else
    jac run --dev
fi
