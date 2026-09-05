# T4 — Small state bugs: banner ownership, duplicate add, recordFailure order (B5–B7, P2)

Read `AGENTS.md` and `docs/spec.md` (invariant I-10) before starting. Three
small, independent fixes in `Mitori/App/MitoriModel.swift` (+ bridge for one).
Land them as three separate commits.

## Fix 1 — Banner ownership (B5)

`bannerMessage` is a single global string. `applyPostRefreshState` sets
`bannerMessage = nil` on any success, so account A's success clears account
B's visible error.

- Track which account owns the current banner (e.g. a private
  `bannerAccountID: String?` set wherever `bannerMessage` is set from an
  account-scoped path).
- On success for account X, clear the banner only if it is unowned or owned by
  X. On failure for X, overwrite banner + owner (latest failure wins —
  unchanged UX).
- `deleteAccount` clears the banner only if owned by the deleted account.
- Keep the public surface `bannerMessage: String?` — UI code must not change.

Acceptance: test — account B fails (banner shows B's issue), then account A
refreshes successfully → banner still shows B's issue; B then succeeds → banner
clears.

## Fix 2 — Duplicate add preserves history (B6)

`addAccount` for an email that already exists silently overwrites the stored
meta via `sessionBridge.login(...)` with `existing: nil`, wiping
`balanceSnapshot`, `lastRefreshAt`, and the configured `probeBundleID`.

- In `MitoriModel.addAccount`, when `account(with: accountID)` exists, treat
  the flow as a credential update: pass the existing meta through so the
  bridge preserves snapshot/history (the bridge's internal
  `authenticate(..., existing:)` already supports this — `login` currently
  hardcodes `existing: nil`; extend the `AppleSessionBridging.login`
  signature or route through `reauthenticate` semantics, whichever keeps the
  protocol smaller).
- Preserve the stored `probeBundleID` when the add-form probe field is empty;
  a non-empty form value wins.
- No duplicate row may ever be created (the id is the lowercased email —
  unchanged).

Acceptance: test — add account, refresh so it has a snapshot, add the same
email again with a new password → resulting account keeps snapshot,
`lastRefreshAt`, and probe; secret is updated.

## Fix 3 — recordFailure ordering (B7)

`recordFailure` mutates `accounts[index] = failed` **before** any
`operationIsCurrent` check; a superseded operation can briefly publish stale
failure state.

- Drop the eager in-memory mutation (the `repository.upsert` path already
  reassigns `accounts` behind a generation check), or move it behind
  `operationIsCurrent`. Prefer deleting the redundant write.

Acceptance: existing concurrency tests in `MitoriTests/MitoriModelTests.swift`
stay green; add one if the superseded case isn't covered.

## Verification

- `mise run test-macos` green after each of the three commits.

## Out of scope

- Refresh policy (T5), parser (T1/T2), any fork changes, per-account runtime
  actor (§5 "Later").
