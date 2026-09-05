# T6a — Port ApplePackage subset into `Mitori/AppleStore/` (verbatim)

Read `AGENTS.md` and `docs/spec.md` (§5 target architecture, D-2, D-3)
before starting. Precondition: D-4 is closed (T5 done) — do not port while the
live auth behavior is unresolved.

## Goal

Move the Mitori-relevant subset of the fork
(`/Users/star/Developer/zach-repo/ApplePackage`, branch `zach/mitori`, at the
currently pinned revision) into this repo as app-target source. **Verbatim
port: behavior-identical, no refactors, no renames beyond namespacing.**
"Move" and "improve" never share a commit — improvements are T6b.

## Scope (from the fork)

- `Commands/Authenticate.swift`, `Commands/Bag.swift`, `Commands/Lookup.swift`
- `Models/Account.swift`, `Supplement/Cookie.swift`,
  `Supplement/AppleActionSigner.swift`, `Supplement/Strings.swift` (auth
  subset), `Supplement/Errors.swift`/`Ensure.swift` as needed to compile
- `Configuration/` — userAgent, deviceIdentifier, storefront/countryCode
  table, `storeAPIHost(pod:)`, HTTP client config
- `Sources/CommerceKitSigner/` (Obj-C, ~140 lines) → into the app target with
  a bridging header
- Fork tests that cover the above (`AuthenticateTests` redirect/rewrite/cookie
  cases) → `MitoriTests/AppleStore/`, converted to Swift Testing **only if**
  they are XCTest; skip live-network cases.

Destination: `Mitori/AppleStore/` (synchronized folder reference — files on
disk join the target; per `AGENTS.md` no project regeneration). Keep the
AsyncHTTPClient usage **for now** — it compiles against the still-present SPM
dependency; the transport swap is T6b. The SPM dependency is removed in T6c
only.

## Wiring

- `LiveAppleAuthenticator` in `Mitori/Services/AppleSessionBridge.swift` and
  the `Lookup`/`Configuration`/`Cookie`/`Account` call sites switch from
  `import ApplePackage` to the local module namespace (plain types in-target;
  resolve name collisions with an `AppleStore` enum-namespace prefix if
  needed).
- The seams `AppleAuthenticating` / `BalanceRefreshing` and every existing
  test double stay untouched.

## Acceptance criteria

- No Mitori source file imports `ApplePackage` anymore (grep proves it);
  the SPM package is still referenced by the project but only as a leftover
  for T6c.
- Ported fork tests run in `MitoriTests` and pass.
- App behavior unchanged: `mise run test-macos` green,
  `mise run build-macos` packages, `mise run run-macos` launches and an
  existing account renders.
- `Mitori/Resources/OpenSourceLicenses.md` gains/keeps MIT attribution for
  ApplePackage (Lakr233) and ipatool (majd) covering the ported code.

## Verification

- `mise run test-macos`, `mise run build-macos`, launch check via
  `mise run run-macos`.

## Out of scope

- URLSession transport, typed errors, redirect allowlist (T6b). Removing the
  SPM dependency (T6c). Any behavior change at all.
