# T6b — AppleStore on URLSession + typed errors + redirect allowlist (fixes B4)

Read `AGENTS.md` and `docs/spec.md` (invariants I-1, I-2, I-3, I-4; §4)
before starting. Precondition: T6a landed. This is the "improve" half — land
as a sequence of small commits, one concern each.

## Goal

1. **Transport:** replace AsyncHTTPClient in `Mitori/AppleStore/` with a
   single URLSession-based transport (ephemeral configuration, cookies off —
   the module manages cookies explicitly like today, redirects disabled via
   delegate exactly like `BalanceProbeClient`'s
   `BalanceProbeRedirectDelegate`). HTTP/1.1 semantics and the
   connect/read timeouts from the fork's `Configuration` carry over.
2. **Redirect allowlist (B4, I-2):** one shared validator used by **both**
   authenticate and probe paths — `https`, no user/password in URL, port
   nil/443, host allowlist: `buy.itunes.apple.com`,
   `downloaddispatch.itunes.apple.com`, `auth.itunes.apple.com`,
   `init.itunes.apple.com`, `p\d+-buy.itunes.apple.com`. Generalize from
   `BalanceProbeClient.validatedRedirectURL` / `isTrustedStoreHost` and
   delete the duplicate in `BalanceService.swift` in favor of the shared one.
   The authenticate redirect resolution (`resolvedRedirectURL`) must go
   through this validator — a credential-bearing POST never follows an
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
- One redirect validator implementation in the codebase (grep for
  `isTrustedStoreHost` — exactly one).
- A unit test proves an authenticate 3xx with `Location: http://evil.example/`
  or an unknown https host is rejected with `untrustedRedirect` and no
  follow-up request is issued (inject a transport stub).
- A unit test proves `codeRequired` / `invalid2FACode` / session-expiry map to
  `MitoriError.twoFactorCodeRequired` / `.invalidTwoFactorCode` /
  `.sessionExpired` via typed cases, and the string-matching branches are gone.
- All redirect/rewrite behavior tests ported in T6a still pass unchanged —
  they are the protocol truth.
- `mise run test-macos` green; `mise run build-macos` packages.

## Live check

After landing, one supervised G3 run (login → refresh → refresh, no-probe
account) before T6c. Requires Zach.

## Out of scope

- Removing the SPM dependency (T6c). Parser redesign beyond what T1/T2 already
  fixed. Per-account runtime actor.
