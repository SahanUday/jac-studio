"""Structural extraction: calls the Node/TypeScript-compiler-API shim (extract/extract.mjs) as
a subprocess. This is the one genuinely non-Jac piece of the tool, by design, not by default --
Jac's npm interop is confirmed client-only, so a plain server-side Jac module cannot reach the
TypeScript compiler API directly. See docs/translator-strategy.md and the tracking branch's
2026-08-22-npm-interop-server-only-blocked.md for the spike that settled this.
"""

import subprocess;
import json;

glob DEFAULT_EXTRACT_SCRIPT: str = "extract/extract.mjs";

def run_extraction(
    source_path: str,
    test_path: str = "",
    script_path: str = DEFAULT_EXTRACT_SCRIPT,
) -> dict {
    args = ["node", script_path, source_path];
    if test_path {
        args.append(test_path);
    }
    result = subprocess.run(args, capture_output=True, text=True);
    if result.returncode != 0 {
        message = (
            f"extraction failed (exit code {result.returncode})\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        );
        raise RuntimeError(message);
    }
    return json.loads(result.stdout);
}
