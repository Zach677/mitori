# T6a - Port ApplePackage subset into `Mitori/AppleStore/` (verbatim)

Read `AGENTS.md` and `docs/spec.md` (§5 target architecture, D-2, D-3)
before starting. Precondition: D-4 is closed (T5 done) - do not port while the
live auth behavior is unresolved.

## Goal

Move the Mitori-relevant subset of the fork
(`/Users/star/Developer/zach-repo/ApplePackage`, branch `zach/mitori`, at the
currently pinned revision) into this repo as app-target source. **Verbatim
port: behavior-identical, no refactors, no renames beyond namespacing.**
"Move" and "improve" never share a commit - improvements are T6b.

## Scope (from the fork)

- `Commands/Authenticate.swift`, `Commands/Bag.swift`, `Commands/Lookup.swift`
- `Models/Account.swift`, `Supplement/Cookie.swift`,
  `Supplement/AppleActionSigner.swift`, `Supplement/Strings.swift` (auth
  subset), `Supplement/Errors.swift`/`Ensure.swift` as needed to compile
- `Configuration/` - userAgent, deviceIdentifier, storefront/countryCode
  table, `storeAPIHost(pod:)`, HTTP client config
- `Sources/CommerceKitSigner/` (Obj-C, ~140 lines) → into the app target with
  a bridging header
- Fork tests that cover the above (`AuthenticateTests` redirect/rewrite/cookie
  cases) → `MitoriTests/AppleStore/`, converted to Swift Testing **only if**
  they are XCTest; skip live-network cases.

Destination: `Mitori/AppleStore/` (synchronized folder reference - files on
disk join the target; per `AGENTS.md` no project regeneration). Keep the
AsyncHTTPClient usage for now; explicitly wire the required existing package
products to the app target if the port imports them. Do not assume transitive
product visibility. The transport swap is T6b and package removal is T6c.
Port the verified T5 redirect validator and safe diagnostics unchanged.

Before editing, inventory all referenced fork symbols and their source files,
including `AuthenticationResult`, and record the exact source revision. The
list above is a starting set, not permission to omit compile dependencies.
The old package still links CommerceKitSigner: avoid duplicate Objective-C
runtime class/C symbols by prefixing the local copy during coexistence. Treat
this as a mechanical wiring change, not a signer behavior rewrite.

## Wiring

- `LiveAppleAuthenticator` in `Mitori/Services/AppleSessionBridge.swift` and
  the `Lookup`/`Configuration`/`Cookie`/`Account` call sites switch from
  `import ApplePackage` to the local module namespace (plain types in-target;
  resolve name collisions with an `AppleStore` enum-namespace prefix if
  needed).
- Preserve the behavior contracts of `AppleAuthenticating` / `BalanceRefreshing`.
  Update package-owned type references and imports in both app code and test
  doubles. Keep behavioral assertions unchanged. A fake returning the old
  package's `Account` cannot satisfy an interface returning a local `Account`.

## Acceptance criteria

- No source in `Mitori/` or `MitoriTests/` imports `ApplePackage`; verify with
  `rg -n 'import ApplePackage' Mitori MitoriTests` (expected no matches, exit 1).
  Existing package products remain only for the transitional transport/linkage.
- Existing account metadata and cookie/secret fixtures decode identically with
  the local types. Verify account ID, store, pod, cookie expiry/domain/path,
  snapshot timestamps, and persisted issue state; never use real secrets.
- The launch log contains no duplicate Objective-C class warning. The local
  signer is used by authenticate and succeeds in the supervised G3 run.
- Ported fork tests run in `MitoriTests` and pass.
- App behavior unchanged: `mise run test-macos` green,
  `mise run build-macos` produces the app bundle, `mise run run-macos` launches and an
  existing account renders.
- `Mitori/Resources/OpenSourceLicenses.md` gains/keeps MIT attribution for
  ApplePackage (Lakr233) and ipatool (majd) covering the ported code.

## Verification

- G1, G2, G3, G5, and G6, plus the supervised owned-probe check in spec section 7.
  Capture failures separately for development and community signing modes.
- Record the source-to-destination file map and mechanical type/symbol changes.
  More than eight files may change in this port; review the entire map.
- Roll back the wiring/port as one unit if equivalence fails, preserving account
  data and T5's validated redirect/logging protections.

## Out of scope

- URLSession transport, typed errors, and redirect-validator consolidation (T6b).
  Removing the SPM dependency (T6c). Any behavior change at all.
