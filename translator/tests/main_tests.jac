"""Tests for main.jac's CLI wiring: build_parser()'s defaults, subcommand dispatch, and
required-argument enforcement. Only possible because main.jac uses `with entry:__main__` --
a plain `with entry` block runs on every import, which would fire the live CLI dispatch (and
call sys.exit) the moment this test file imported build_parser.
"""

import from main { build_parser }

test "add subcommand parses required args and applies documented defaults" {
    parser = build_parser();
    args = parser.parse_args(["add", "--vscode-root", "/vs", "--source", "src/a.ts", "--test-root", "src/test"]);
    assert args.command == "add";
    assert args.vscode_root == "/vs";
    assert args.source == "src/a.ts";
    assert args.test_root == "src/test";
    assert args.id == "";
    assert args.test_file == "";
    assert args.risk_tier == "low";
    assert args.phase == "0";
    assert args.manifest == "manifest.toml";
}

test "status subcommand needs no extra required arguments" {
    parser = build_parser();
    args = parser.parse_args(["status"]);
    assert args.command == "status";
}

test "extract subcommand requires id and vscode-root" {
    parser = build_parser();
    args = parser.parse_args(["extract", "--id", "prefix-sum-computer", "--vscode-root", "/vs"]);
    assert args.command == "extract";
    assert args.id == "prefix-sum-computer";
    assert args.vscode_root == "/vs";
}

test "verify subcommand requires id" {
    parser = build_parser();
    args = parser.parse_args(["verify", "--id", "interval-tree"]);
    assert args.command == "verify";
    assert args.id == "interval-tree";
}

test "block subcommand requires id and summary, error defaults empty" {
    parser = build_parser();
    args = parser.parse_args(["block", "--id", "x", "--summary", "oops"]);
    assert args.command == "block";
    assert args.id == "x";
    assert args.summary == "oops";
    assert args.error == "";
}

test "top-level --manifest flag overrides the default" {
    parser = build_parser();
    args = parser.parse_args(["--manifest", "/tmp/custom.toml", "status"]);
    assert args.manifest == "/tmp/custom.toml";
}

test "a missing required subcommand argument raises SystemExit, not a silent bad default" {
    parser = build_parser();
    try {
        parser.parse_args(["verify"]);
        assert False, "expected SystemExit for a missing required --id";
    } except SystemExit {}
}

test "an unknown subcommand raises SystemExit" {
    parser = build_parser();
    try {
        parser.parse_args(["not-a-real-command"]);
        assert False, "expected SystemExit for an unrecognized subcommand";
    } except SystemExit {}
}
