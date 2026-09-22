# jac-studio

VS Code's capabilities and UX, rebuilt as a Jac web app — AI-first, not a literal clone. Monaco is
the editor engine, proven libraries cover already-solved problems, and Jac carries the
architecture, the services and the AI-native layer. Ship the web app first; desktop comes last by
bundling the same client.

## Non-negotiables

- **Run it before claiming it works.** `jac check <file>`, then `jac test <file>`. "The code looks
  right" is not a result — state what you verified and what you assumed.
- **Never commit to `main`.** Feature branch, PR, left unmerged for review. No AI co-author
  trailers or AI-authorship mentions in commits or PR bodies.
- **Log real Jac blockers** to the challenge tracker in the same sitting. Silently working around a
  Jac limitation is the one thing this project exists to avoid.
- **Stop every dev server you start** — ports 8000/8001 clear before the turn ends.
- **Reuse before building.** A solved problem gets a proven library; Jac effort goes to the
  architecture, Jac-specific workflows, and the AI layer. When you adopt a library, record what it
  gives you in `docs/libraries/<name>.md`.

## Prose budget

This codebase is kept deliberately lean. Text earns its place or it goes.

- **Module docstring: 5 lines max.** What it is, any non-obvious constraint, a link. Nothing else.
- **Comments: rare, one line**, and only for what the code cannot say — an ordering constraint, a
  workaround, a real gotcha. Never restate the line below it.
- **Never in source code**: changelogs, dated "as of" narratives, QA-pass reports, design-rationale
  essays, scope justifications, chains of cross-references. These go in `docs/decisions/` as an
  ADR; the code links to it in one line if it needs to at all.
- **Docs**: prefer tables and short sections over paragraphs. A doc past ~200 lines wants
  splitting. Current state belongs in `architecture.md`; how-we-got-here belongs in an ADR.

## Where things live

| Question | File |
|---|---|
| What are we building, in what order | `docs/roadmap.md` |
| How is it put together, right now | `docs/architecture.md` |
| Why was it done this way | `docs/decisions/` |
| What does this library give us | `docs/libraries/` |
| Does VS Code have X, do we cover it | `docs/vscode-complete-triage.md` |
| What broke in Jac and what we did | challenge tracker (`jac-studio-challenge-tracking`) |

## Don't work around jac/jaseci bugs — need to fix them upstream

A core goal of QuakePassion is to exercise and improve **jac/jaseci** itself (the `jaseci` submodule). Working around a jac bug hides the defect and defeats that goal.

When a reasonable Jac idiom — especially Object-Spatial Programming (OSP) constructs — fails, errors, or behaves unexpectedly:

1. First verify it's actually a jac/jaseci defect, not a misuse (check docs/examples/tests in the submodule).
2. If it is the language/runtime, **pause the affected work and create a proper upstream fix**: isolate a minimal repro, investigate the root cause on on upstream `jac` main.
3. Create the github issue on `jaseci-labs/jac`. Report the issue with repro script and validation results. The issue should be readable and easy to understand, so don't add too much unnecessary texts, but it should be informative. Also you can you flowcharts and diagrams to explain complex parts, it will help to get the better understanding easily.
4. **Resume the original QuakePassion work using the locally fixed compiler/runtime** until make the PR and awaits review. Do not wait for the upstream merge unless it is technically necessary. Keep track of the local compiler patches required for validation.
5. Do **not** rewrite engine code to avoid the construct. If an reported issue and its suggested fix cannot be completed, explain the concrete blocker and continue any independent work that remains possible.

After you can log those blockers on challenge tracker (`jac-studio-challenge-tracking`) with the issue link.

Skills carry the detail and load themselves when relevant: `jac-language` before writing any
`.jac`, `jac-studio-architecture` before designing a component, `jac-studio-code-style` before a
module of real size, `jac-studio-testing` before touching tests, `jac-studio-libraries` before
adopting a package.
