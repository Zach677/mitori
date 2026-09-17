# T6b - AppleStore on URLSession + typed errors + redirect allowlist (consolidates the B4 fix)

Read `AGENTS.md` and `docs/spec.md` (invariants I-1, I-2, I-3, I-4; §4)
before starting. Precondition: T6a landed. This is the "improve" half - land
as a sequence of small commits, one concern each.

## Goal

1. **Transport:** replace AsyncHTTPClient in `Mitori/AppleStore/` with a
   single URLSession-based transport (ephemeral configuration, cookies off -
   the module manages cookies explicitly like today, redirects disabled via
   delegate exactly like `BalanceProbeClient`'s
   `BalanceProbeRedirectDelegate`). Preserve request method, body, headers,
   explicit cookies, cancellation, and bounded request duration. Do not promise
   identical HTTP versions or one-to-one connect/read timeout knobs across
   clients. Document the URLSession timeout mapping and test timeout/cancellation
   failure paths; any required behavioral difference must be reviewed.
2. **Redirect allowlist (B4, I-2):** one shared validator used by **both**
   authenticate and probe paths - `https`, no user/password in URL, port
   nil/443, host allowlist: `buy.itunes.apple.com`,
   `downloaddispatch.itunes.apple.com`, `auth.itunes.apple.com`,
   `init.itunes.apple.com`, and whole-host `^p[0-9]+-buy\.itunes\.apple\.com$`
   after lowercasing. Generalize from
   `BalanceProbeClient.validatedRedirectURL` / `isTrustedStoreHost` and
   delete the duplicate in `BalanceService.swift` in favor of the shared one.
   The authenticate redirect resolution (`resolvedRedirectURL`) must go
   through this validator - a credential-bearing POST never follows an
   unvalidated Location.
3. **Typed errors (I-3):** introduce `StoreAuthError` per spec §4. The
   authenticate/bag/probe paths throw typed cases.
   `MitoriError.mapApplePackage` (bridge) and the string-matching branches in
   `MitoriError.map` (`"verification code"`, `"invalid or expired 2fa code"`,
   `"password token is expired"`, `"unsupported store identifier"`) are
   replaced by typed-case mapping and deleted.
4. Migrate probing: `BalanceProbeClient` moves into `Mitori/AppleStore/` and
   shares the transport + validator (one HTTP stack, I-1).

## Acceptance criteria

- No `AsyncHTTPClient`/`NIO` import anywhere under `Mitori/` (grep).
- One redirect validator definition serves all redirect-following paths.
  Inspect callers as well as definitions; a grep occurrence count includes calls
  and is not proof that only one implementation exists.
- A unit test proves an authenticate 3xx with `Location: http://evil.example/`
  or an unknown https host is rejected with `untrustedRedirect` and no
  follow-up request is issued (inject a transport stub).
- A unit test proves `codeRequired` / `invalid2FACode` / session-expiry map to
  `MitoriError.twoFactorCodeRequired` / `.invalidTwoFactorCode` /
  `.sessionExpired` via typed cases, and the string-matching branches are gone.
- T5/T6a trusted redirect and protocol fixtures still pass. Reject HTTP,
  credentials in URLs, non-443 ports, unknown hosts, deceptive suffixes, and
  malformed targets with zero follow-up requests. Test relative trusted URLs,
  explicit port 443, mixed-case hosts, and redirect exhaustion.
- Test typed mappings for session expiry, code required, invalid code, app not
  owned, unsupported storefront, transport timeout, and malformed responses.
  Include misleading English messages to prove text cannot select a state.
- Test cancellation during auth/probe and the next operation after cancellation;
  no stuck refreshing state or stale credential write is allowed. Cookie
  propagation, signer body bytes, and POST redirect behavior retain fixtures.
- Run the T2 wrong-source/no-data tests and T3 multi-tick suspension tests against
  the new live implementations through a stub transport, not only fake bridges.
- `mise run test-macos` green; `mise run build-macos` produces the app bundle.

## Live check

G1, G2, G3, G5, and G6 are required, plus a supervised owned-probe refresh.
Complete these on this transport before T6c. Compare request counts and data
sources with the T5 baseline. A skipped or cached request cannot pass G3.

## Out of scope

- Removing the SPM dependency (T6c). Parser redesign beyond what T1/T2 already
  fixed. Per-account runtime actor.
