"""Outcome recorder: scaffolds a challenge-tracker log entry on translation failure, so logging
a blocker in the same sitting it's hit costs nothing extra.

Writes into a local staging directory (translator/blocked/, gitignored) rather than directly
onto the `tracking` branch's log/ -- that branch isn't checked out while this tool runs on
`main`, git branches don't let you write across each other's working trees. Landing a scaffolded
entry is a manual step: `git checkout tracking`, move the file into `log/`, fill in the TODO,
rebuild the site (`python3 site/build.py`), commit, push. See translator/README.md.
"""

import os;
import re;
import from datetime { date }
import from .manifest { ManifestEntry }

def slugify(text: str) -> str {
    s: str = text.lower();
    s = re.sub(r"[^a-z0-9]+", "-", s);
    return s.strip("-");
}

def scaffold_blocker(
    record: ManifestEntry,
    summary: str,
    error_text: str,
    severity: str = "major",
    subsystem: str = "translator",
    output_dir: str = "blocked",
) -> str {
    today = date.today().isoformat();
    slug = slugify(summary) or slugify(record.id) or "entry";
    filename = f"{today}-{slug}.md";
    os.makedirs(output_dir, exist_ok=True);
    out_path = os.path.join(output_dir, filename);

    body = (
        "---\n"
        f"id: {today}-{slug}\n"
        f"date: {today}\n"
        "category: translator-blocker\n"
        f"severity: {severity}\n"
        "status: open\n"
        f"phase: {record.phase}\n"
        f"subsystem: {subsystem}\n"
        "jac_version: \"\"\n"
        f"related_vscode_ref: \"{record.upstream_path}\"\n"
        "upstream_issue: \"\"\n"
        f"tags: [translator, {record.id}]\n"
        "---\n\n"
        f"Hit while translating `{record.upstream_path}` (manifest id `{record.id}`) via the "
        f"TS->Jac translator. Jac attempt: `{record.jac_path}`.\n\n"
        "**Error**:\n\n"
        "```\n"
        f"{error_text}\n"
        "```\n\n"
        "**Plan**: TODO -- fill in before moving this into the tracking branch's log/.\n"
    );

    with open(out_path, "w", encoding="utf-8") as f {
        f.write(body);
    }
    return out_path;
}
