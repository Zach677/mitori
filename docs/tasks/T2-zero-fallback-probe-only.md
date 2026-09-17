# T2 - Source-specific balance parsing and probe-only zero fallback (B2, P0)

Read `AGENTS.md`, `docs/spec.md` I-4, and the common gates before starting.
This card owns strict field selection. Do not defer it to T6b.

## Goal

Use explicit paths selected by `BalanceSnapshot.Source`. Remove arbitrary
recursive searches for `balance` and `creditDisplay`, including the empty-value
search. Preserve the existing supported value representations at allowed paths.

Use the following ordered path lists, drawn from the current parser and fixtures:

| Source | Allowed paths, in precedence order |
|--------|------------------------------------|
| authentication | `accountInfo.balance`, `accountInfo.creditDisplay`, `balance`, `creditDisplay` |
| probe | `creditDisplay`, `balance`, `songList[0].creditDisplay`, `songList[0].balance`, `songList[0].metadata.creditDisplay`, `songList[0].metadata.balance` |

The lists are separate even where root-level paths overlap. A new field path
requires a sanitized endpoint fixture and an explicit spec/card update.

Select the first valid non-empty candidate. Only if none exists may an empty
string at an allowed probe `creditDisplay` path mean zero. Missing fields are
not empty strings. An authentication response without a valid candidate throws
`MitoriError.balanceNotFound`; empty auth credit must never imply zero.

Verify that `AppleSessionBridge.authenticate` keeps `existing?.balanceSnapshot`
and its timestamp when auth parsing produces no data. A new no-probe account
stays at nil without a fabricated balance or issue. No bridge policy change is
required for this behavior.

## Files

- `Mitori/Services/BalanceParser.swift`
- Parser tests in `MitoriTests/MitoriCoreTests.swift`
- `MitoriTests/AppleSessionBridgeTests.swift` and sanitized fixture data

## Acceptance criteria

1. The existing auth/probe success fixtures return their expected value, source,
   and `rawFieldPath`. Test each allowed path and precedence when two are present.
2. An empty allowed probe credit field returns zero only when no valid candidate
   exists. A completely absent field throws `balanceNotFound` for either source.
3. Empty auth credit throws `balanceNotFound`; a no-probe login then has nil
   balance and no issue. Reauth with an existing snapshot retains its value,
   source, and `fetchedAt`/`lastRefreshAt` without making it appear fresh.
4. `unrelated.balance`, `unrelated.creditDisplay`, auth `songList[0].balance`,
   and probe `accountInfo.balance` never produce a candidate or zero fallback.
   Include a response with misleading fields before a valid allowed candidate.
5. Whitespace-only credit counts as empty only at an allowed probe credit path.
   Boolean/unsupported values do not become money. Malformed plist data fails
   without overwriting the saved snapshot. T1's numeric cases remain green.

## Verification

G1. Identify a failing pre-fix regression for both fabricated zero and unrelated
recursive matches. Map each criterion to named tests in the completion report.

## Out of scope

Numeric separator rules (T1), UI copy, and protocol transport migration (T6).
