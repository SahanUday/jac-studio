# M6 — Quality floor

**Status**: complete, 2026-09-27

Make "it works" checkable by something other than a person.

## Shipped

| What |
|---|
| `.github/workflows/ci.yml`: `jac check .` and `jac test src` on every PR and push to `main`, using a checksum-verified `jac` binary — no other toolchain setup, since the binary bundles its own Python and bun runtimes. |
| First test coverage for workbench state: `session_restore.jac` pulls the shell's session-restore decision (empty session → pass through; saved session → replace all five fields together, `cursor_positions` ahead of `groups`) into a pure function `jac test` can reach, since the entry block itself is client-placed and untestable. 3 new tests. |
| [ADR 0080](../decisions/0080-retire-self-registering-contribution-criterion.md): retires the M4 self-registering-contribution exit criterion. The centralized command/view lists stay; self-registration is deferred to M12, against a real extension consumer. |

## Decisions
[ADR 0080](../decisions/0080-retire-self-registering-contribution-criterion.md).

## Deviations from plan

- Wiring CI to a real `jac` binary (not the dev-mode source build every local run uses) surfaced
  that every `jac.toml` in the repo — root plus the four `internal/*` spikes — still used the
  pre-migration `entry-point = "main.jac"` form; current jaseci requires a dotted module name with
  no extension. Fixed all five; not originally scoped, but CI couldn't exist without it.
- CI's first real run failed on `git_service.test.jac`'s `commit_changes` test: it shells out to a
  real `git commit`, relying on the committer identity a real dev machine already has configured.
  A bare runner has none. Fixed by giving the runner one, not by changing `commit_changes` — depending
  on the machine's own git identity is correct production behavior.
- CI pins `jac` to release `v0.37.3` rather than floating jaseci `main`. The local jaseci checkout
  was found to be ~293 commits behind real upstream `main`; running against true `main` HEAD
  produces 14 further `jac check` failures unrelated to this milestone. `v0.37.3` is the newest
  release the codebase is fully green against.

## Left open

- The 14-failure gap against current jaseci `main` is undiagnosed. Syncing to main (fixing or
  filing upstream issues for each, then bumping the CI pin) is an unscheduled follow-up.
- M4's carried-over criterion is the only item resolved here; M6's own exit bar (CI gates
  regressions, session-restore is under test) is met, but workbench state coverage is still
  minimal — one decision function, not the shell's other state transitions.
