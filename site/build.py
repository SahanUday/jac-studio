#!/usr/bin/env python3
"""Builds the challenge-tracker static site: reads /log/*.md, emits /dist/{index.html,data.json}.

Deliberately dependency-free (stdlib only) and deliberately not written in Jac — this tool reports
on jac-lang's own rough edges, so it shouldn't depend on the thing it's tracking. See
docs/challenge-tracking.md on the `main` branch for the full design rationale.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT / "log"
SITE_DIR = ROOT / "site"
DIST_DIR = ROOT / "dist"

FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?\n)---\s*\n(.*)\Z", re.DOTALL)


def parse_scalar(value: str):
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [item.strip().strip('"').strip("'") for item in inner.split(",")]
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def parse_frontmatter(text: str) -> tuple[dict, str]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        raise ValueError("missing frontmatter block")
    raw_fm, body = m.group(1), m.group(2)
    fm: dict = {}
    for line in raw_fm.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = parse_scalar(value)
    return fm, body.strip()


def load_entries() -> list[dict]:
    entries = []
    for path in sorted(LOG_DIR.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        try:
            fm, body = parse_frontmatter(text)
        except ValueError as e:
            print(f"skipping {path.name}: {e}", file=sys.stderr)
            continue
        fm["body"] = body
        fm["_file"] = path.name
        entries.append(fm)
    entries.sort(key=lambda e: (e.get("date", ""), e.get("id", "")), reverse=True)
    return entries


def main() -> None:
    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True)

    entries = load_entries()
    (DIST_DIR / "data.json").write_text(
        json.dumps({"entries": entries, "generated_from": len(entries)}, indent=2),
        encoding="utf-8",
    )
    shutil.copy(SITE_DIR / "index.html", DIST_DIR / "index.html")
    print(f"built {len(entries)} entries -> {DIST_DIR}")


if __name__ == "__main__":
    main()
