# T5 - No-probe refresh policy and live 302 evidence (B8, P1)

Read `AGENTS.md` and `docs/spec.md` I-2/I-6/I-7/I-8 and D-4. T1-T4 must pass
before this card. Zach supervises live login and credential entry. This card
contains an evidence gate, not a promise that the cookie-less option is correct.
If neither policy passes, record the result and stop; T6 stays blocked.

## Safety prerequisites

- Before a live request, validate credential-bearing authenticate redirects in
  the pinned fork using the same URL constraints as the probe validator. Reject
  HTTP, userinfo, non-443 ports, unknown hosts, and Apple-looking suffix attacks.
  Test that rejection issues zero follow-up requests; retain trusted redirects.
  Keep this safety change separate from cookie-policy changes. T6a ports it;
  T6b later consolidates both validators. Do not wait for T6b to protect login.
- Do not enable the fork's current `APLogger.verbose` for real accounts. Its
  request logger exposes Cookie and its response logger exposes header values.
  Use a sanitized probe that emits only operation/attempt numbers, endpoint
  labels, cookie counts, status, header names, body size, and body type.
  No raw URLs, query strings, header values, bodies, or identifiers are logged.
- Before live use, capture logger output from synthetic fixtures with sentinel
  secrets in Cookie, Set-Cookie, authorization, token, GUID, URL, and body fields.
  Assert that no sentinel appears and that the required safe fields do appear.
  Keep a regression for redirect rejection and one for logging redaction.

## Evidence and decision

1. Record the pinned fork revision and build/signing mode. The historical
   `3b535f1` retry is a hypothesis, not a verified solution.
2. On the existing policy, run G3: login, completed manual refresh, then another
   completed manual refresh. Count authenticate requests for each operation,
   including internal retries and redirects. No cached/skipped operation passes.
3. If stored-cookie refresh succeeds only after the cookie-clear retry, test
   cookie-less-first on the same no-probe refresh path under supervision.
   Use it only if G3 passes with no extra 2FA prompt and the trace confirms that
   the failed cookie-backed attempt was removed. Do not infer causality merely
   from two green UI refreshes. If the retry was not used, keep the verified
   existing policy; there is no evidence to justify changing it.
4. If cookie-less-first fails or adds 2FA friction, retain the stored-cookie
   policy only if its G3 passed. If neither passes, leave B8 and D-4 open,
   attach sanitized evidence, and stop without adding a new redirect workaround.
5. A cookie-less policy applies only to ordinary no-probe refresh. A global
   `code.isEmpty` condition in shared `reauthenticate` is insufficient: probe
   session recovery and explicit user reauthentication also use an empty code.
   Preserve those paths and interactive 2FA.
6. Remove the fork fallback only when tests show its other callers no longer
   need it. Otherwise document its distinct scope and bound. Never add a second
   fallback around the same failed request. Record the selected policy and
   evidence in D-4, with the exact verified fork and app revisions.

## Refresh behavior

Do not add the proposed 60-second cache shortcut. A completed manual refresh
must perform a real attempt; repeated clicks while one operation is in flight
use the existing model operation guard. Automatic refresh remains interval,
backoff, lock-screen, and state gated (T3). No new timing preference is needed.

## Files

- `Mitori/Services/AppleSessionBridge.swift` and bridge/model tests
- The pinned `Zach677/ApplePackage` checkout, branch `zach/mitori`, for scoped
  redirect/logging safety and, only when justified, fallback removal
- `Mitori.xcodeproj/project.pbxproj` and its `Package.resolved` for a verified pin

## Acceptance criteria

1. Redirect and sentinel-redaction regressions pass before live use. Request
   traces contain the safe fields and zero secrets.
2. G3 passes on the selected policy: each operation actually authenticates and
   gets new balance data. Record request counts, not just three UI successes.
3. Stub tests prove correct cookies for no-probe refresh, probe-expiry recovery,
   explicit reauth with an empty code, and interactive 2FA. Only the proven
   no-probe path changes. `codeRequired` becomes `needsVerification`, without
   another automatic login on subsequent due ticks.
4. Concurrent refresh clicks start one operation. A new refresh after completion
   starts another real attempt, even within 60 seconds. Automatic interval,
   backoff, screen-lock, and T3 suspension tests still pass.
5. The final fork pin resolves to the tested revision. D-4 is closed with
   evidence, or remains open and the card is `blocked`. No partial green result
   marks B8 fixed. Record B4's safety fix separately from B8's live outcome.

## Verification and recovery

G1, G2, and G3; run the fork's existing offline tests for any fork changes and
record the exact command. G4 applies to the decision update. Fork safety fixes
can stand alone when the cookie investigation is blocked. If a policy change
fails acceptance, restore the last verified cookie policy while retaining
redirect validation and safe logging. Stored accounts and secrets stay intact.
Commit/push to either repository requires explicit authorization.
