# T3 - Automatic refresh never sends a password (B3, B9, P1)

Read `AGENTS.md` and `docs/spec.md` §3, I-6, I-9, D-9 first.

## Goal

Implement the §3 refresh table:

- `AppleSessionBridging.refreshBalance` gets `allowsReauthentication: Bool`.
  The model passes `isManualRefresh`. With `false`, the bridge only probes:
  zero authenticate calls on every path, and `sessionExpired` is thrown as is.
- `MitoriModel.shouldAutoRefresh` skips no-probe accounts and accounts whose
  `lastIssue` kind is anything other than `network`.
- Manual path (B3): after a successful reauth, record every probe failure in
  `lastIssue` and keep the auth snapshot. A probe `sessionExpired` right after
  that reauth becomes `balanceUnavailable`.
- Remove the D-8 gate in `MitoriModel.normalized` (and its `previous:`
  parameter); I-6 makes it unnecessary. Replace its test.
- Update user copy: README "Add an account" and Highlights, the Settings
  auto-refresh help text, and a CHANGELOG Unreleased entry. Say that automatic
  refresh needs a probe app and that accounts without one refresh on demand.

## Files

`Mitori/Services/AppleSessionBridge.swift`, `Mitori/App/MitoriModel.swift`,
`Mitori/UI/SettingsViewController.swift`, README/CHANGELOG, and the bridge,
model, and auto-refresh tests (including `SessionBridgeStub`).

## Acceptance

1. Two due automatic ticks on a no-probe account: zero bridge calls.
2. Automatic probe gets `sessionExpired`: zero auth calls, issue
   `sessionExpired`, and the next two due ticks make zero calls. The pause
   survives a reload from `AccountStore`.
3. A probe account with a `network` issue still retries after backoff; a second
   account keeps refreshing while the first one is paused.
4. Manual refresh: probe expiry → one auth → probe expiry gives one auth call,
   two probe calls, the auth snapshot kept, and `balanceUnavailable`. A later
   successful manual refresh clears the issue and automatic refresh resumes.
5. Changing or removing the probe clears probe-related issues only.
6. G5: the paused account shows its issue and a manual refresh works from the UI.

## Verification

G1, G5. Use stubs with call counts and the injected `now`; no sleeps.
