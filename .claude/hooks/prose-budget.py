#!/usr/bin/env python3
"""Advisory PostToolUse check: flags prose that exceeds the budget in CLAUDE.md. Never blocks."""
import json
import sys

JAC_DOCSTRING_MAX = 5
JAC_PROSE_RATIO_MAX = 0.15
JAC_RATIO_MIN_LINES = 50  # below this, a single legal docstring dominates the ratio
DOC_LINES_MAX = 200


def module_docstring_len(lines):
    for i, line in enumerate(lines):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith('"""'):
            if s.endswith('"""') and len(s) > 5:
                return 1
            for j in range(i + 1, len(lines)):
                if '"""' in lines[j]:
                    return j - i + 1
            return len(lines) - i
        return 0
    return 0


def prose_lines(lines):
    total, in_block = 0, False
    for line in lines:
        s = line.strip()
        ticks = s.count('"""')
        if in_block:
            total += 1
            if ticks:
                in_block = False
        elif s.startswith("#"):
            total += 1
        elif s.startswith('"""'):
            total += 1
            in_block = ticks == 1
    return total


def main():
    try:
        path = json.load(sys.stdin).get("tool_input", {}).get("file_path", "")
        if not path:
            return
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except Exception:
        return

    warnings = []
    if path.endswith(".jac"):
        doc = module_docstring_len(lines)
        if doc > JAC_DOCSTRING_MAX:
            warnings.append(
                f"module docstring is {doc} lines (budget {JAC_DOCSTRING_MAX}). "
                "Keep what it is + non-obvious constraints; move rationale to docs/decisions/."
            )
        if len(lines) >= JAC_RATIO_MIN_LINES:
            ratio = prose_lines(lines) / len(lines)
            if ratio > JAC_PROSE_RATIO_MAX:
                warnings.append(
                    f"{ratio:.0%} of this file is comments/docstrings "
                    f"(budget {JAC_PROSE_RATIO_MAX:.0%})."
                )
    elif path.endswith(".md") and "/docs/" in path and len(lines) > DOC_LINES_MAX:
        warnings.append(
            f"{len(lines)} lines (budget {DOC_LINES_MAX}). Split it, or move history to "
            "docs/decisions/."
        )

    if warnings:
        msg = f"Prose budget — {path.rsplit('/', 1)[-1]}: " + " ".join(warnings)
        json.dump(
            {
                "systemMessage": msg,
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": msg,
                },
            },
            sys.stdout,
        )


if __name__ == "__main__":
    main()
