# Task cards

Each file here is a self-contained prompt for a coding agent. Paste the whole
card as the task. Cards assume the agent has repo access and has read
`AGENTS.md` and `docs/spec.md` (every card restates this requirement).

## Rules

- One card per agent session. Do not batch cards.
- Before coding, report `pwd`, `git status --short --branch -uall`, and
  `git rev-parse HEAD`. Confirm that this checkout contains the assigned spec
  and card and that its code matches their assumptions. A stale local
  `origin/main` is not proof of GitHub's current head. Do not merge, reset,
  stash, switch branches, or overwrite unrelated work to make the tree match.
- Read spec section 7 for the shared gates. Use `todo`, `in-progress`,
  `blocked`, or `done @commit`; missing live evidence stays `blocked`.
- Card text describing commits means commit boundaries when committing is
  authorized. It does not itself authorize commit, push, or release.
- A card is done when its **Acceptance criteria** all hold and its
  **Verification** commands pass. "Tests are green" alone is not done.
- If a card conflicts with `docs/spec.md`, the spec wins; stop and report
  instead of improvising (spec-first rule).
- After a card lands, update the Status column here and the defect register in
  `docs/spec.md` §6.

## Board

| Card | Title | Depends on | Status |
|------|-------|------------|--------|
| T1 | BalanceParser: thousands vs decimal separators | - | todo |
| T2 | Strict source paths and probe-only zero fallback | T1 | todo |
| T3 | Record probe failures and pause automatic reauth loops | T2 | todo |
| T4 | Small state bugs: banner ownership, duplicate add, recordFailure order | - | todo |
| T5 | Safe diagnostics, redirect validation, no-probe refresh policy | T1-T4 passed; Zach at keyboard for live evidence | todo |
| T6a | Port ApplePackage subset into `Mitori/AppleStore/` (verbatim) | T5 resolved (D-4 closed) | todo |
| T6b | AppleStore on URLSession + typed errors + redirect allowlist | T6a | todo |
| T6c | Drop ApplePackage and preserve generated license notices | T6b, its G3 and owned-probe live check passed | todo |

Dispatch order: T1 → T2 → T3 → T4 → T5 → T6a → T6b → T6c.
T4 has no semantic dependency on T1-T3, but execute it sequentially to avoid
edits to shared model/test files. T5 can close only after its evidence passes;
T6 must not start on a proposed or partially verified cookie policy.

## Invariant ownership

| Requirement | Implementation owner | Acceptance evidence |
|-------------|----------------------|---------------------|
| I-1 one transport | T6b; dependency removal in T6c | No NIO imports; actual auth/probe requests use one transport |
| I-2 trusted redirects | T5 safety prerequisite; T6b consolidation | Rejected target causes zero follow-up requests |
| I-3 typed protocol/state errors | T6b | Typed mapping cases, no protocol-message classification |
| I-4 source-specific fields | T2 | Allowed paths, wrong-source fields, absent/empty values |
| I-5 amount parsing | T1 | Exact Decimal and rendered JPY regression |
| I-6 refresh discipline | T3 and T5 | Multiple due ticks, in-flight guard, real manual requests |
| I-7 evidence before workarounds | T5 | Sanitized trace, bounded fallback, D-4 decision |
| I-8 no secret logging | T5; preserved in T6 | Sentinel secrets absent from captured log output |
| I-9 visible probe failure | T3 | Snapshot retained, issue visible, no scheduled login loop |
| I-10 account-local state | T4 | Interleaved account success/failure and stale operations |
| I-11 native project shape | T6a-T6c | Xcode/mise builds, no standalone package or generator |

A completion report must map each card criterion to evidence. Passing a build
or grep alone does not prove runtime behavior. Planning revisions leave the
implementation statuses unchanged until code and required checks are complete.
