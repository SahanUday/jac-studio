#!/usr/bin/env bash
# Lands a finished challenge-tracker blocker entry (scaffolded by `translator ... block` into
# internal/translator/blocked/) onto the `tracking` branch in one shot: checkout, copy, rebuild the
# site, commit, push, switch back to wherever you started.
#
# Deliberately plain bash, not Jac -- this script touches the `tracking` branch itself, the
# observability backstop. If it broke because of a Jac issue, you could lose the ability to
# report that issue. Same reasoning that kept the tracker's own site/build.py in Python, not
# Jac -- see docs/translator-strategy.md and internal/translator/README.md.
#
# Scope: git mechanics only. The **Plan** section of the file must already be filled in --
# this script never writes content, only moves an already-finished file across branches.
#
# Usage: internal/translator/land-blocker.sh internal/translator/blocked/<file>.md

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <path-to-finished-blocker-md>" >&2
  exit 1
fi

SRC_FILE="$1"

if [ ! -f "$SRC_FILE" ]; then
  echo "error: file not found: $SRC_FILE" >&2
  exit 1
fi

if grep -q '\*\*Plan\*\*: TODO' "$SRC_FILE"; then
  echo "error: $SRC_FILE still has an unfilled Plan section ('**Plan**: TODO') -- fill it in before landing" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
FILENAME="$(basename "$SRC_FILE")"

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree has uncommitted changes on '$ORIGINAL_BRANCH' -- commit or discard them first (this script will not stash)" >&2
  exit 1
fi

# Resolve to an absolute path before switching branches: internal/translator/ isn't part of tracking's
# tree, so it survives the checkout as an untracked leftover, but a relative path could
# resolve differently once we're operating from a different point in that same working tree.
SRC_FILE_ABS="$(cd "$(dirname "$SRC_FILE")" && pwd)/$FILENAME"

echo "==> switching to tracking (from $ORIGINAL_BRANCH)"
git checkout tracking

cleanup() {
  echo "==> switching back to $ORIGINAL_BRANCH"
  git checkout "$ORIGINAL_BRANCH" || echo "warning: could not switch back to $ORIGINAL_BRANCH automatically -- do it by hand" >&2
}
trap cleanup EXIT

echo "==> pulling latest tracking"
git pull --ff-only origin tracking

DEST="log/$FILENAME"
if [ -e "$DEST" ]; then
  echo "error: $DEST already exists on tracking -- refusing to overwrite" >&2
  exit 1
fi

cp "$SRC_FILE_ABS" "$DEST"

echo "==> rebuilding the tracker site"
python3 site/build.py

git add "$DEST"

SLUG="${FILENAME%.md}"
SLUG="${SLUG#*-*-*-}"
TITLE="$(echo "$SLUG" | tr '-' ' ')"
git commit -m "Log challenge: $TITLE"
git push origin tracking

echo "==> landed $DEST, pushed to tracking"
echo "==> removing local staged copy: $SRC_FILE_ABS"
rm -f "$SRC_FILE_ABS"
