"""CLI entry point for the jac-studio TS->Jac translator tooling.

Five subcommands, each a thin wrapper over src/*.jac:
  add      eligibility-check a TS source file and queue it in the manifest
  status   print the manifest grouped by status
  extract  run structural extraction (exports, signatures, doc comments) for a queued module
  verify   jac check + jac test a module's Jac output, land or block it
  block    mark a module blocked and scaffold a tracker-entry draft

See README.md for usage and docs/translator-strategy.md (main jac-studio branch) for the design.
"""

import argparse;
import sys;
import os;
import json;

import from src.manifest { ManifestEntry, load_manifest, save_manifest, find_entry }
import from src.eligibility { check_eligibility, DEFAULT_MAX_LINES }
import from src.extract { run_extraction }
import from src.verify { verify }
import from src.tracker_entry { scaffold_blocker }

"""--source/--test-root/--test-file are given relative to --vscode-root, and stored that
way in the manifest too -- an absolute, machine-specific path in a git-tracked file isn't
portable to anyone else running this tool."""
def cmd_add(args: any) -> int {
    max_lines: int = int(args.max_lines);
    phase: int = int(args.phase);

    abs_source = os.path.join(args.vscode_root, args.source);
    abs_test_root = os.path.join(args.vscode_root, args.test_root);
    abs_test_file = os.path.join(args.vscode_root, args.test_file) if args.test_file else "";

    result = check_eligibility(abs_source, abs_test_root, max_lines, abs_test_file);
    print(f"eligible: {result.eligible}  ({result.line_count} lines)");
    if result.test_path {
        print(f"  test file: {result.test_path}");
    }
    for reason in result.reasons {
        print(f"  - {reason}");
    }
    if not result.eligible {
        return 1;
    }

    entries = load_manifest(args.manifest);
    entry_id = args.id if args.id else os.path.splitext(os.path.basename(args.source))[0];
    existing = find_entry(entries, entry_id);
    if existing {
        print(f"'{entry_id}' already in manifest with status '{existing.status}' -- not re-added");
        return 0;
    }

    test_upstream_path = os.path.relpath(result.test_path, args.vscode_root) if result.test_path else "";
    entries.append(ManifestEntry(
        id=entry_id,
        upstream_path=args.source,
        test_upstream_path=test_upstream_path,
        status="queued",
        risk_tier=args.risk_tier,
        phase=phase,
    ));
    save_manifest(entries, args.manifest);
    print(f"added '{entry_id}' to {args.manifest}");
    return 0;
}

def cmd_status(args: any) -> int {
    entries = load_manifest(args.manifest);
    if not entries {
        print("manifest is empty");
        return 0;
    }
    by_status: dict[str, list[ManifestEntry]] = {};
    for e in entries {
        by_status.setdefault(e.status, []).append(e);
    }
    for status in ["queued", "in-progress", "landed", "blocked"] {
        group = by_status.get(status, []);
        if not group {
            continue;
        }
        print(f"{status} ({len(group)}):");
        for e in group {
            print(f"  {e.id}  [{e.risk_tier}]  {e.upstream_path}");
        }
    }
    return 0;
}

def cmd_extract(args: any) -> int {
    entries = load_manifest(args.manifest);
    record = find_entry(entries, args.id);
    if not record {
        print(f"no manifest entry '{args.id}'");
        return 1;
    }
    abs_source = os.path.join(args.vscode_root, record.upstream_path);
    abs_test = os.path.join(args.vscode_root, record.test_upstream_path) if record.test_upstream_path else "";
    data = run_extraction(abs_source, abs_test);
    print(json.dumps(data, indent=2));
    return 0;
}

def cmd_verify(args: any) -> int {
    entries = load_manifest(args.manifest);
    record = find_entry(entries, args.id);
    if not record {
        print(f"no manifest entry '{args.id}'");
        return 1;
    }
    if not record.jac_path {
        print(f"'{args.id}' has no jac_path set yet -- nothing to verify");
        return 1;
    }
    result = verify(record.jac_path);
    if result.passed {
        record.status = "landed";
        print(f"'{args.id}' verified and marked landed");
    } else {
        record.status = "blocked";
        print(f"'{args.id}' failed verification at stage '{result.failure_stage}':");
        print(result.check_output if result.failure_stage == "check" else result.test_output);
    }
    save_manifest(entries, args.manifest);
    return 0 if result.passed else 1;
}

def cmd_block(args: any) -> int {
    entries = load_manifest(args.manifest);
    record = find_entry(entries, args.id);
    if not record {
        print(f"no manifest entry '{args.id}'");
        return 1;
    }
    out_path = scaffold_blocker(record=record, summary=args.summary, error_text=args.error);
    record.status = "blocked";
    save_manifest(entries, args.manifest);
    print(f"scaffolded {out_path}; '{args.id}' marked blocked");
    return 0;
}

def build_parser() -> any {
    parser = argparse.ArgumentParser(prog="translator", description="jac-studio TS->Jac porting tool");
    parser.add_argument("--manifest", `default="manifest.toml");
    sub = parser.add_subparsers(dest="command", required=True);

    add_p = sub.add_parser("add", help="eligibility-check a TS source file and queue it");
    add_p.add_argument("--vscode-root", required=True, help="path to the upstream vscode checkout");
    add_p.add_argument("--source", required=True, help="TS module path, relative to --vscode-root");
    add_p.add_argument("--test-root", required=True, help="dir to search for the test file, relative to --vscode-root");
    add_p.add_argument("--id", `default="");
    add_p.add_argument(
        "--test-file", `default="",
        help="explicit upstream test path, bypassing basename search (for a module tested "
             "only as part of a larger unit, e.g. an inner class of a multi-file directory)",
    );
    add_p.add_argument("--risk-tier", `default="low", choices=["low", "foundational"]);
    add_p.add_argument("--phase", `default="0");
    add_p.add_argument("--max-lines", `default=str(DEFAULT_MAX_LINES));
    add_p.set_defaults(func=cmd_add);

    status_p = sub.add_parser("status", help="print manifest summary");
    status_p.set_defaults(func=cmd_status);

    extract_p = sub.add_parser("extract", help="run structural extraction for a queued module");
    extract_p.add_argument("--id", required=True);
    extract_p.add_argument("--vscode-root", required=True);
    extract_p.set_defaults(func=cmd_extract);

    verify_p = sub.add_parser("verify", help="jac check + jac test a landed module");
    verify_p.add_argument("--id", required=True);
    verify_p.set_defaults(func=cmd_verify);

    block_p = sub.add_parser("block", help="mark a module blocked and scaffold a tracker entry");
    block_p.add_argument("--id", required=True);
    block_p.add_argument("--summary", required=True);
    block_p.add_argument("--error", `default="");
    block_p.set_defaults(func=cmd_block);

    return parser;
}

with entry {
    parser = build_parser();
    args = parser.parse_args();
    sys.`exit(args.func(args));
}
