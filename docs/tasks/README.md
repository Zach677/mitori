# Task cards

Each file here is a self-contained prompt for a coding agent. Paste the whole
card as the task. Cards assume the agent has repo access and has read
`AGENTS.md` and `docs/spec.md` (every card restates this requirement).

## Rules

- One card per agent session. Do not batch cards.
- A card is done when its **Acceptance criteria** all hold and its
  **Verification** commands pass. "Tests are green" alone is not done.
- If a card conflicts with `docs/spec.md`, the spec wins; stop and report
  instead of improvising (spec-first rule).
- After a card lands, update the Status column here and the defect register in
  `docs/spec.md` §6.

## Board

| Card | Title | Depends on | Status |
|------|-------|------------|--------|
| T1 | BalanceParser: thousands vs decimal separators | — | todo |
| T2 | Zero-balance fallback is probe-only | — | todo |
| T3 | Stop swallowing probe failures after reauth | — | todo |
| T4 | Small state bugs: banner ownership, duplicate add, recordFailure order | — | todo |
| T5 | No-probe refresh policy + live 302 evidence | T1–T3 recommended, Zach at keyboard | todo |
| T6a | Port ApplePackage subset into `Mitori/AppleStore/` (verbatim) | T5 resolved (D-4 closed) | todo |
| T6b | AppleStore on URLSession + typed errors + redirect allowlist | T6a | todo |
| T6c | Drop the ApplePackage SPM dependency | T6b, G3 green | todo |

Suggested dispatch order: T1 → T2 → T3 → T4 (any order, independent), then T5
when Zach can supervise a live run, then T6a → T6b → T6c.
