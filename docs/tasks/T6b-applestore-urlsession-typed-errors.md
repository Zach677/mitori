# T6b - One URLSession transport, redirect allowlist, typed errors (B4)

Read `AGENTS.md` and `docs/spec.md` I-1, I-2, I-3, §4 first. Precondition: T6a.
One concern per commit.

## Goal

1. **Transport (I-1):** replace AsyncHTTPClient in `Mitori/AppleStore/` with
   one URLSession transport: ephemeral, cookies handled by the module,
   redirects disabled by a delegate (as in `BalanceProbeRedirectDelegate`).
   Keep method, body, headers, explicit cookies, cancellation, and a bounded
   timeout. Move `BalanceProbeClient` onto the same transport.
2. **Redirect allowlist (I-2, B4):** one validator for authenticate and probe:
   `https`, no userinfo, port nil/443, lowercased host in
   `buy.itunes.apple.com`, `downloaddispatch.itunes.apple.com`,
   `auth.itunes.apple.com`, `init.itunes.apple.com`, or matching
   `^p[0-9]+-buy\.itunes\.apple\.com$`. Delete the copy in `BalanceService.swift`.
3. **Typed errors (I-3):** add `StoreAuthError` (§4). Delete
   `mapApplePackage`, the message-matching branches in `MitoriError.map`, and
   the `customerMessage` string match in `parseKnownFailure`.

## Acceptance

1. No `AsyncHTTPClient`/`NIO` import under `Mitori/`.
2. A stub transport proves that an authenticate 3xx to `http://`, an unknown
   host, a deceptive suffix, userinfo, or a non-443 port throws
   `untrustedRedirect` with zero follow-up requests. Relative trusted URLs,
   explicit 443, and mixed-case hosts are followed.
3. Typed mapping tests for code required, invalid code, session expiry, app
   not owned, unsupported storefront, timeout, and malformed response,
   including a misleading English message that must not select a state.
4. Cancellation during auth or probe leaves no stuck refreshing state.
5. T2 parser and T3 refresh-policy tests pass through the stub transport.

## Verification

G1, G2, G5.
