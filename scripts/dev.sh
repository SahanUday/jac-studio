#!/usr/bin/env bash
# One-command local dev startup: full clean, prune stale embedded-Postgres databases
# (orphaned only -- jac db prune never touches a project that still exists on disk),
# install dependencies, then start the dev server.
#
# Enable the terminal yourself first if you want it, in jac.toml:
#   [terminal]
#   enabled = true
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Clearing any stale process on ports 8000/8001"
for port in 8000 8001; do
    pid="$(lsof -ti ":${port}" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        echo "    killing stale process on :${port} (pid ${pid})"
        kill -9 $pid 2>/dev/null || true
    fi
done

echo "==> Cleaning stale .jac build artifacts (data, cache, packages, client)"
jac clean --all --force

echo "==> Pruning orphaned databases from the shared embedded Postgres cluster"
jac db prune -y

echo "==> Installing dependencies"
jac install

echo "==> Starting jac-studio"
if command -v capped >/dev/null 2>&1; then
    exec capped --mem 4G -- jac run --dev
else
    exec jac run --dev
fi
