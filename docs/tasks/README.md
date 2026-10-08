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
  `blocked`, or `done @commit`.
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
| T1 | BalanceParser: thousands vs decimal separators | - | done @c011c00 |
| T2 | Strict source paths and probe-only zero fallback | T1 | done @9191bac |
| T3 | Automatic refresh never sends a password | T2 | done @2908d9d |
| T4 | Banner ownership, duplicate add, recordFailure order | T3 | todo |
| T6a | Port the ApplePackage subset into `Mitori/AppleStore/` (verbatim) | T4 | todo |
| T6b | One URLSession transport, redirect allowlist, typed errors | T6a | todo |
| T6c | Drop the ApplePackage SPM dependency | T6b | todo |
| T5 | Safe diagnostics and the supervised live run (B8, B10) | T6c; Zach at keyboard | todo |

Dispatch order (D-10): T3 → T4 → T6a → T6b → T6c → T5. T4 has no semantic
dependency on T3 but shares model files, so run it after T3. T5 runs last on
the final build and doubles as the release G3.
