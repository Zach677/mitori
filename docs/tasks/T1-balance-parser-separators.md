# T1 — BalanceParser: thousands vs decimal separators (B1, P0)

Read `AGENTS.md` and `docs/spec.md` (invariants I-4, I-5) before starting.

## Context

`BalanceParser.numericValue(from:)` in `Mitori/Services/BalanceParser.swift`
treats a comma-only amount as a decimal comma: `"¥1,000"` → `1.000` →
`Decimal(1)`. `BalanceSnapshot.localizedDisplayText` then re-formats that
number, so a Japanese account with ¥1,000 credit renders as **¥1**. Any
storefront that prints thousands separators without decimals (JPY always, USD
`$1,234`) is off by orders of magnitude. European decimal commas (`1,50 €`)
must keep working.

## Goal

Disambiguate comma-only (and dot-only) amounts:

- Multiple occurrences of the same separator ⇒ it is a grouping separator
  (`1,234,567` → `1234567`).
- Single comma with exactly 3 digits after it and ≥1 digit before ⇒ grouping
  (`1,000` → `1000`). Otherwise decimal (`1,50` → `1.50`).
- Mirror the same rule for dot-only strings (`1.000` in EU formats is one
  thousand; `1.50` is a decimal). Note: today dot-only strings are passed
  through unchanged — that silently misreads EU `1.000`; fix it with the same
  trailing-group rule.
- Mixed separators keep the existing last-separator-wins logic (already
  correct for `$1,234.56` and `1.234,56 €`).

Keep it a pure heuristic inside `numericValue`; do not thread locale/country
into the parser in this task.

## Files

- `Mitori/Services/BalanceParser.swift` (`numericValue(from:)`)
- `MitoriTests/` — extend the existing parser tests (see `MitoriCoreTests.swift`
  for where BalanceParser is currently exercised; add cases near those or in a
  dedicated `BalanceParserTests` if one exists).

## Acceptance criteria

All of these parse to the exact Decimal shown:

| Input | Expected |
|-------|----------|
| `$1,234.56` | 1234.56 |
| `¥1,000` | 1000 |
| `¥1,000,000` | 1000000 |
| `$1,234` | 1234 |
| `1.234,56 €` | 1234.56 |
| `1,50 €` | 1.50 |
| `1.000 €` | 1000 |
| `¥0` | 0 |
| `$0.00` | 0 |
| `-12.34` | -12.34 |

And: `localizedDisplayText` for a JPY snapshot built from `"¥1,000"` with
`countryCode: "JP"` renders ¥1,000 (not ¥1). Add that as a test too.

## Verification

- `mise run test-macos` green, including the new cases.

## Out of scope

- Locale-aware parsing, currency detection changes, `zeroCandidate` behavior
  (that is T2). Do not touch `AppleSessionBridge` or the fork.
