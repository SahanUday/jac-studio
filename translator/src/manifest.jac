"""The manifest: the ledger of TS->Jac translation targets and their status.

Kept as a plain TOML file on disk (not Jac graph persistence) so it stays diffable and
reviewable in git/PR history -- see docs/translator-strategy.md on the main jac-studio branch
for the design rationale. Every function that reads or writes it lives here.
"""

import tomllib;
import tomli_w;
import os;

obj ManifestEntry {
    has id: str;
    has upstream_path: str;
    has upstream_commit: str = "";
    has jac_path: str = "";
    has test_upstream_path: str = "";
    has test_jac_path: str = "";
    has status: str = "queued";       # queued | in-progress | landed | blocked
    has risk_tier: str = "low";       # low | foundational
    has verification: str = "tests"; # tests | tests+differential
    has phase: int = 0;
    has notes: str = "";
}

def entry_to_dict(e: ManifestEntry) -> dict {
    return {
        "id": e.id,
        "upstream_path": e.upstream_path,
        "upstream_commit": e.upstream_commit,
        "jac_path": e.jac_path,
        "test_upstream_path": e.test_upstream_path,
        "test_jac_path": e.test_jac_path,
        "status": e.status,
        "risk_tier": e.risk_tier,
        "verification": e.verification,
        "phase": e.phase,
        "notes": e.notes,
    };
}

def entry_from_dict(m: dict) -> ManifestEntry {
    return ManifestEntry(
        id=m["id"],
        upstream_path=m.get("upstream_path", ""),
        upstream_commit=m.get("upstream_commit", ""),
        jac_path=m.get("jac_path", ""),
        test_upstream_path=m.get("test_upstream_path", ""),
        test_jac_path=m.get("test_jac_path", ""),
        status=m.get("status", "queued"),
        risk_tier=m.get("risk_tier", "low"),
        verification=m.get("verification", "tests"),
        phase=m.get("phase", 0),
        notes=m.get("notes", ""),
    );
}

def load_manifest(path: str = "manifest.toml") -> list[ManifestEntry] {
    if not os.path.exists(path) {
        return [];
    }
    with open(path, "rb") as f {
        data = tomllib.load(f);
    }
    entries: list[ManifestEntry] = [];
    for m in data.get("modules", []) {
        entries.append(entry_from_dict(m));
    }
    return entries;
}

def save_manifest(entries: list[ManifestEntry], path: str = "manifest.toml") -> None {
    modules = [entry_to_dict(e) for e in entries];
    with open(path, "wb") as f {
        tomli_w.dump({"modules": modules}, f);
    }
}

def find_entry(entries: list[ManifestEntry], entry_id: str) -> ManifestEntry | None {
    for e in entries {
        if e.id == entry_id {
            return e;
        }
    }
    return None;
}
