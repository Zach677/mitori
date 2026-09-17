# T3 - Record probe failures and stop automatic reauth loops (B3, P1)

Read `AGENTS.md`, `docs/spec.md` I-6/I-9, and the common gates before starting.

## Goal

After successful authentication, record every probe failure in `lastIssue` and
keep the authentication snapshot. Map a probe `sessionExpired` immediately after
that authentication to `balanceUnavailable`. Other errors keep their kind.

Changing the kind alone does not stop future logins. In
`MitoriModel.shouldAutoRefresh`, skip probe accounts whose persisted issue is
`balanceUnavailable`. This includes unavailable balance data and invalid probe
configuration: the user must retry or correct the probe. Network-only failures
still use the existing interval/backoff policy. Accounts needing 2FA also skip
automatic refresh until the user recovers them.

Manual refresh or explicit reauthentication can perform one recovery attempt:
at most one reauth and one post-reauth probe per operation. Successful probe
recovery clears the pause. A failed recovery preserves an existing
`balanceUnavailable` pause and exposes the latest error through the existing
account error surface. It must not replace the pause with a retryable network
issue and silently restart scheduled logins. If recovery requires 2FA, record
`requiresVerification` instead; that state also remains paused and must show the
verification action. Changing/removing the probe clears
that probe-related pause only; unrelated verification issues remain intact.
Use the existing issue kind, not a new persistent flag or message matching.

## Files

- `Mitori/Services/AppleSessionBridge.swift`
- `Mitori/App/MitoriModel.swift`
- Existing bridge, model, and auto-refresh tests in `MitoriTests/`

## Acceptance criteria

1. Probe expiry, one successful reauth, then probe expiry yields one auth call,
   two probe calls, a retained auth snapshot, and `balanceUnavailable`.
2. Feed that result back into the model; advance an injected clock beyond both
   backoff and refresh interval. Two automatic ticks add zero auth/probe calls.
   Persist/reload metadata and repeat: the pause survives restart.
3. A second account still refreshes. A `network` issue without a pre-existing
   pause still retries on schedule. `requiresVerification` causes zero automatic
   auth calls across two due ticks.
4. Explicit manual recovery succeeds and clears the pause; later auto refresh
   runs normally. Failed recovery keeps the pause and shows its error. Repeat
   the due-tick test after a network failure during manual recovery.
5. Changing/removing the probe allows a new refresh. No-probe login, successful
   probes, and unrelated verification issues retain their intended behavior.
6. A network error after reauth is visible as `network` when no prior pause
   exists. Missing auth balance preserves the prior snapshot and its timestamp.
7. In the running app, the rejected-probe account shows attention and its issue;
   manual recovery is reachable, and another account's success does not hide it
   after T4 lands. Do not require T4 for the account-local T3 check.

## Verification

G1 and G5. Use deterministic stubs for call counts and an injected clock; no
sleep-based tests or real Apple failure injection. Report each criterion by
number and the test/manual result that proves it.

## Out of scope

Cookie policy (T5), actor redesign, new retry settings, and data-format changes.
