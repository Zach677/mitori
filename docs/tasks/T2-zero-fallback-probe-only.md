# T2 — Zero-balance fallback is probe-only (B2, P0)

Read `AGENTS.md` and `docs/spec.md` (invariant I-4) before starting.

## Context

`BalanceParser.parse(plistData:source:)` in
`Mitori/Services/BalanceParser.swift` falls back to
`emptyCreditDisplayPath(...)` → `zeroCandidate(...)`: an **empty**
`creditDisplay` string anywhere in the plist becomes a `numericValue: 0`
snapshot. That rule is documented behavior for the **probe** endpoint
(changelog 0.2.0), but it now also runs for `source: .authentication` — an
authenticate response with an empty/absent credit field fabricates a `$0.00`
balance instead of "no data". This is the likely cause of freshly added
accounts all showing `$0.00`.

## Goal

- Apply the empty-`creditDisplay`-means-zero fallback only when
  `source == .probe`.
- For `.authentication`, if neither the explicit paths nor the recursive scan
  finds a non-empty balance field, `parse` throws `MitoriError.balanceNotFound`
  (existing behavior for the no-candidate case).
- Confirm the caller behavior stays correct: `AppleSessionBridge.authenticate`
  wraps the auth-source parse in `try?` and keeps `existing?.balanceSnapshot`,
  so a login with no parsable balance keeps the previous snapshot / stays nil.
  Do not change the bridge in this task; just verify with a test.

## Files

- `Mitori/Services/BalanceParser.swift`
- `MitoriTests/` parser tests + `MitoriTests/AppleSessionBridgeTests.swift`
  (add a fixture-based case: auth plist whose `creditDisplay` is empty → login
  result has `balanceSnapshot == nil` and `lastIssue == nil`).

## Acceptance criteria

- Probe plist with empty `creditDisplay` still parses to a zero snapshot
  (existing tests keep passing).
- Auth plist with empty `creditDisplay` and no other balance field throws
  `balanceNotFound` from `parse`.
- Login via `AppleSessionBridge` with such an auth plist yields
  `balanceSnapshot == nil`, no fabricated zero, no `lastIssue` for the no-probe
  case.

## Verification

- `mise run test-macos` green.

## Out of scope

- Numeric separator parsing (T1). Recursive-scan strictness redesign (target
  state §4/§5 of the spec, lands with T6b). UI copy.
