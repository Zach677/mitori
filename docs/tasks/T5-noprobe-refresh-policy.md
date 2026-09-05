# T5 — No-probe refresh policy + live 302 evidence (B8, P1; closes D-4)

Read `AGENTS.md` and `docs/spec.md` (invariants I-6, I-7, I-8; decision D-4)
before starting. **This card needs Zach at the keyboard** for the live phases.
Agents never initiate live logins with real credentials on their own.

## Context

Refresh of a no-probe account performs a silent reauthentication with stored
cookies (`AppleSessionBridge.refreshBalance` → `reauthenticate` →
`secret.cookies`). Live behavior: fresh login (with `cookies: []`) succeeds,
but the very next refresh fails `authentication failed: failed to retrieve
redirect location (HTTP 302)`. Fork commit `3b535f1` (retry once with cookies
cleared on 3xx-without-Location) is pinned but **unverified**. Two prior 3xx
patches were wrong guesses; per I-7 we collect headers before changing anything
else.

## Phase 1 — Evidence (live, Zach supervising)

1. `mise run run-macos`; on the failing no-probe account: manual refresh twice.
2. Record for each authenticate attempt (enable the fork's `APLogger` verbose
   mode or equivalent): request URL, cookie **count** (never values), response
   status, header **names** (note whether `Location` / `x-apple-orig-url`
   exist), body length, body type (plist vs HTML). No secrets in any artifact
   (I-8).
3. Outcomes:
   - **Refresh succeeds twice** → `3b535f1` works; go to Phase 2 decision (a).
   - **Still fails** → attach the header record to the card and go to Phase 2
     decision (b).

## Phase 2 — Decision + implementation

**(a) `3b535f1` works:** the cookie-clear retry means every no-probe refresh
costs up to two full password logins. Implement cookie-less-first in Mitori:
`AppleSessionBridge.reauthenticate` sends `cookies: []` when `code.isEmpty`
(silent path); interactive reauth (user-entered 2FA code) keeps stored
cookies. Then revert `3b535f1` in the fork and bump the pin (no stacked
workarounds, D-4) — unless the live record shows cookie-less also 302s, in
which case keep `3b535f1` and document why in the spec Decision Log.

**(b) still failing:** do **not** add another 3xx special case. Bring the
header record back to the spec's Decision Log, update D-4 with the evidence,
and stop — the fix gets designed against data, not guessed.

In both branches, also implement the freshness guard (I-6): a manual refresh
of a no-probe account whose snapshot is younger than 60 s is a no-op returning
the cached result (debounce against accidental double-click login storms).
Auto refresh is already interval-gated in `MitoriModel.shouldAutoRefresh` —
do not duplicate that gate in the bridge.

Watch: if silent cookie-less reauth starts returning `codeRequired` in the
live run (2FA friction), record it — that is the strongest argument for
keeping cookie-based reauth and its retry patch, and D-4 flips accordingly.

## Files

- `Mitori/Services/AppleSessionBridge.swift`
- `MitoriTests/AppleSessionBridgeTests.swift` (cookie-less silent path: assert
  the authenticator stub receives empty cookies when code is empty; debounce
  test with injected clock if feasible)
- Fork (`/Users/star/Developer/zach-repo/ApplePackage`, branch `zach/mitori`)
  only for the possible `3b535f1` revert + Mitori pin bump
  (`Mitori.xcodeproj/project.pbxproj` + `Package.resolved`).

## Acceptance criteria

- G3 gate: login → refresh → refresh on a real no-probe account, three
  successes in a row.
- D-4 in `docs/spec.md` is closed with the chosen policy and a one-paragraph
  evidence summary (no secrets).
- At most **one** mechanism handles the 302 case after this card (I-7).

## Verification

- `mise run test-macos` green; G3 live gate as above.
