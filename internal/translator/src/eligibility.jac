"""Eligibility guard: mechanically checks a candidate TS module against the Tier-1 criteria
from docs/translator-strategy.md before anyone attempts a translation -- pure logic, no DOM/
Electron/browser imports, small, has an upstream test file. A heuristic, not a proof; it fails
fast on the cheap, obvious cases so no one wastes an attempt on something that was always going
to be 'build fresh' territory.
"""

import os;
import re;

glob BANNED_PATH_SEGMENTS: list[str] = [
    "/browser/",
    "/electron-main/",
    "/electron-browser/",
    "/electron-utility/",
];

# Call-shape patterns, not bare substrings: "document." alone false-positives on ordinary
# prose in an editor codebase ("node start offset in document." is a real doc comment on
# pieceTreeBase.ts, not DOM usage -- found while validating this guard against real targets).
glob BANNED_GLOBAL_PATTERNS: list[str] = [
    r"\bdocument\.(getElementById|createElement|querySelector|querySelectorAll|addEventListener|body\b|head\b)",
    r"\bwindow\.(addEventListener|location\b|open\()",
    r"\bnavigator\.",
    r"\blocalStorage\b",
    r"\bHTMLElement\b",
];

glob DEFAULT_MAX_LINES: int = 2000;

obj EligibilityResult {
    has eligible: bool;
    has reasons: list[str];
    has line_count: int;
    has test_path: str = "";
}

"""Search by basename under test_root, not by mirroring the source's directory path --
upstream doesn't always mirror it (prefixSumComputer.test.ts lives under
test/common/viewModel/, not test/common/model/, even though the source is under
common/model/). Not foolproof either: a multi-file module (pieceTreeTextBuffer/) is tested as
a unit by the outer class's test file, not one test per inner file -- check_eligibility's
test_file_override exists for exactly that case."""
def find_test_file(source_path: str, test_root: str) -> str {
    basename = os.path.splitext(os.path.basename(source_path))[0];
    target = f"{basename}.test.ts";
    for (dirpath, _dirnames, filenames) in os.walk(test_root) {
        if target in filenames {
            return os.path.join(dirpath, target);
        }
    }
    return "";
}

def check_eligibility(
    source_path: str,
    test_root: str,
    max_lines: int = DEFAULT_MAX_LINES,
    test_file_override: str = "",
) -> EligibilityResult {
    reasons: list[str] = [];

    if not os.path.exists(source_path) {
        return EligibilityResult(eligible=False, reasons=["source file does not exist"], line_count=0);
    }

    with open(source_path, "r", encoding="utf-8") as f {
        text = f.read();
    }
    lines = text.splitlines();
    line_count = len(lines);

    if line_count > max_lines {
        reasons.append(f"too large: {line_count} lines (max {max_lines})");
    }

    import_lines = [line for line in lines if re.`match(r"^\s*import\b", line)];
    for line in import_lines {
        for seg in BANNED_PATH_SEGMENTS {
            if seg in line {
                reasons.append(f"imports a banned path segment '{seg}': {line.strip()}");
            }
        }
    }

    for pattern in BANNED_GLOBAL_PATTERNS {
        if re.search(pattern, text) {
            reasons.append(f"references a banned DOM/browser API: pattern '{pattern}' matched");
        }
    }

    if test_file_override {
        test_path = test_file_override if os.path.exists(test_file_override) else "";
        if not test_path {
            reasons.append(f"--test-file override does not exist: {test_file_override}");
        }
    } else {
        test_path = find_test_file(source_path, test_root);
        if not test_path {
            reasons.append(
                "no co-located upstream test file found by basename search -- if this module "
                "is tested as part of a larger unit (e.g. an inner class exercised only "
                "through its outer wrapper's test file), pass --test-file explicitly"
            );
        }
    }

    return EligibilityResult(
        eligible=(len(reasons) == 0),
        reasons=reasons,
        line_count=line_count,
        test_path=test_path,
    );
}
