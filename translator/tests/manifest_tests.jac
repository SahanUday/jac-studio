"""Tests for src/manifest.jac -- the ledger read/write/query logic."""

import os;
import tempfile;

import from src.manifest { ManifestEntry, load_manifest, save_manifest, find_entry }

test "round-trips a manifest through save and load" {
    (fd, path) = tempfile.mkstemp(suffix=".toml");
    os.close(fd);
    try {
        entries = [
            ManifestEntry(id="a", upstream_path="src/a.ts", status="queued", risk_tier="low"),
            ManifestEntry(id="b", upstream_path="src/b.ts", status="landed", risk_tier="foundational", phase=1),
        ];
        save_manifest(entries, path);
        loaded = load_manifest(path);

        assert len(loaded) == 2;
        assert loaded[0].id == "a";
        assert loaded[0].status == "queued";
        assert loaded[1].id == "b";
        assert loaded[1].risk_tier == "foundational";
        assert loaded[1].phase == 1;
    } finally {
        os.remove(path);
    }
}

test "load_manifest returns empty list for a missing file" {
    entries = load_manifest("/tmp/definitely-does-not-exist-12345.toml");
    assert entries == [];
}

test "find_entry locates by id, returns None when absent" {
    entries = [ManifestEntry(id="x", upstream_path="src/x.ts")];
    found = find_entry(entries, "x");
    assert found is not None;
    assert found.upstream_path == "src/x.ts";
    assert find_entry(entries, "does-not-exist") is None;
}
