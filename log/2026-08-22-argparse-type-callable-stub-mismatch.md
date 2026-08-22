---
id: 2026-08-22-argparse-type-callable-stub-mismatch
date: 2026-08-22
category: ergonomics
severity: minor
status: resolved
phase: 0
subsystem: tooling
jac_version: "0.36.1 (jac dev build)"
related_vscode_ref: ""
upstream_issue: ""
tags: [python-interop, argparse, typeshed, translator]
---

`argparse.ArgumentParser.add_argument(..., type=int, ...)` — the standard, idiomatic way to
declare a numeric CLI argument in Python — fails `jac check` in a plain Jac CLI script:

```
error[E1053]: Cannot assign int to parameter 'type' of type Callable[[str], Any] | FileType | str
```

`int` genuinely satisfies `Callable[[str], Any]` at runtime (`int("5")` works exactly as
`argparse` expects), but Jac's type checker apparently doesn't structurally recognize a bare
builtin type/constructor as matching a `Callable[...]` parameter type from the typeshed stub for
`add_argument`. Not investigated further whether this is a Jac type-inference gap specifically
around builtin-type-as-callable, or an upstream typeshed-stub precision issue that any strict
checker would hit the same way (mypy has historically had friction here too, depending on stub
version) — worth revisiting only if it recurs somewhere the workaround below doesn't fit.

**Impact on jac-studio**: minor. Affected two argument definitions in the translator's CLI
(`--phase`, `--max-lines`).

**Workaround**: don't fight the stub — declare the argparse field as a plain string (drop
`type=int` entirely) and cast explicitly at the point of use (`int(args.phase)`). Equally clean,
avoids the friction entirely, no loss of correctness since argparse's own runtime validation
of `type=` conversions isn't load-bearing here anyway. `status: resolved`.
