# T4 - Banner ownership, duplicate add, recordFailure order (B5-B7, P2)

Read `AGENTS.md` and `docs/spec.md` I-10 first. Three independent fixes in
`Mitori/App/MitoriModel.swift` (plus the bridge for fix 2); one commit each.

## Fix 1 - Banner ownership (B5)

Track the account that owns `bannerMessage` (private `bannerAccountID`). A
success clears the banner only when the same account owns it. A failure
replaces banner and owner. `deleteAccount` clears only its own banner. An
unowned (global) error is cleared only by its own operation or by dismissal.
The public `bannerMessage: String?` stays unchanged.

Acceptance: B fails → A succeeds → B's banner stays → B succeeds → cleared.
Deleting A keeps B's banner; deleting B clears it. An unowned storage error
survives an unrelated account's success.

## Fix 2 - Duplicate add preserves history (B6)

When `addAccount` finds an existing account (case-insensitive email), pass its
meta to the bridge so snapshot, `lastRefreshAt`, and `probeBundleID` survive.
An empty probe field keeps the stored probe; a non-empty one replaces it.

Acceptance: re-add with a new password and no new balance keeps snapshot,
timestamps, and probe; the secret changes only after authentication and
persistence succeed. A 2FA failure or a secret-save failure leaves the old
account unchanged. No duplicate row in any case.

## Fix 3 - recordFailure order (B7)

Delete the eager `accounts[index] = failed` write; the `repository.upsert` path
already updates `accounts` behind the generation check.

Acceptance: a suspended operation superseded by an update or deletion releases
its failure without changing visible state or stored metadata.

## Verification

G1 after each fix; G5 for fixes 1 and 2 with controlled failures.
