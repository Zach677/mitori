# T3 — Stop swallowing probe failures after reauth (B3, P1)

Read `AGENTS.md` and `docs/spec.md` (invariants I-6, I-9) before starting.

## Context

In `Mitori/Services/AppleSessionBridge.swift`, the private
`authenticate(...)` method's probe-failure catch only records `lastIssue` when
`meta.balanceSnapshot == nil || mappedError.issueKind == .balanceUnavailable`.
Consequence: `refreshBalance` → probe throws `sessionExpired` → reauth → probe
throws `sessionExpired` **again** → the error is dropped and the result looks
like success. The user sees a fresh-looking balance while every refresh cycle
secretly performs a full password login plus two probes, forever. The test
`refreshFallsBackToReauthenticationWhenProbeSessionExpired` currently asserts
this swallow (`lastIssue == nil`) — it enshrines the bug and must change.

## Goal

After a successful (re)authentication, any probe failure is recorded on the
returned meta as `lastIssue` (I-9):

- Map a probe `sessionExpired` that occurs immediately after a successful
  authentication to a `balanceUnavailable`-kind issue with a message along the
  lines of "Probe rejected a fresh session; check the probe app configuration."
  Rationale: a second reauth cannot help, and keeping the `sessionExpired` kind
  would make `MitoriModel`/bridge retry reauth on the next cycle — the exact
  loop we are killing.
- All other probe failure kinds keep their own kind/message, but are always
  recorded (drop the `balanceSnapshot == nil ||` condition).
- The auth-sourced snapshot from the successful authentication is still kept
  on the meta (balance data is real; the issue rides alongside it).

## Files

- `Mitori/Services/AppleSessionBridge.swift`
- `MitoriTests/AppleSessionBridgeTests.swift` — update
  `refreshFallsBackToReauthenticationWhenProbeSessionExpired` to expect
  `lastIssue?.kind == .balanceUnavailable`, and add a case where the probe
  fails with a network error after reauth → `lastIssue?.kind == .network`.

## Acceptance criteria

- Probe failure after reauth always yields a non-nil `lastIssue` on the result.
- Post-reauth probe `sessionExpired` is recorded as `balanceUnavailable`
  (account row shows `.attention`, not an endless reauth loop).
- Login-without-probe and successful-probe paths are unchanged (existing tests
  keep passing).
- `MitoriModel.normalized(...)` picks the issue up and applies backoff
  (`nextEligibleRefreshAt` set) — covered by an assertion or existing model
  tests.

## Verification

- `mise run test-macos` green.

## Out of scope

- Cookie policy / silent reauth strategy (T5). UI changes beyond what the
  existing issue-rendering already does.
