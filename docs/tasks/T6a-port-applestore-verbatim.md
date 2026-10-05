# T6a - Port the ApplePackage subset into `Mitori/AppleStore/` (verbatim)

Read `AGENTS.md` and `docs/spec.md` §5, D-2, D-10 first. Precondition: T4 done.

## Goal

Copy the subset of the fork that Mitori uses
(`/Users/star/Developer/zach-repo/ApplePackage`, at the revision pinned in
`Package.resolved`) into `Mitori/AppleStore/` as app-target source.
Behavior-identical: no refactors, no renames except to resolve collisions.

- Start from `Commands/Authenticate.swift`, `Bag.swift`, `Lookup.swift`, `Search.swift`,
  `Models/Account.swift`, `Supplement/Cookie.swift`, `AppleActionSigner.swift`,
  the needed `Strings`/`Errors`/`Ensure`, and `Configuration/`. Inventory every
  referenced symbol; the list is a starting set, not a limit.
- `Sources/CommerceKitSigner/` joins the app target through a bridging header.
  Prefix the local Objective-C symbols while the package is still linked, to
  avoid duplicate class warnings.
- Keep AsyncHTTPClient for now (T6b swaps it). Link the needed package
  products to the app target explicitly.
- Port the fork's offline tests to `MitoriTests/AppleStore/` (Swift Testing);
  skip live-network tests.
- Switch app code and test doubles from `import ApplePackage` to the local types.

## Acceptance

1. `rg -n 'import ApplePackage' Mitori MitoriTests` has no matches.
2. Existing `accounts.json` and Keychain secret fixtures decode the same with
   local types (account ID, store, pod, cookies, snapshot, issue).
3. Ported tests and all existing tests pass; no duplicate Objective-C class
   warning at launch.
4. `OpenSourceLicenses.md` keeps the ApplePackage and ipatool MIT notices.
5. Record the source revision and the source → destination file map.

## Verification

G1, G2, G5 (launch; an existing account renders). No live login is required:
behavior is unchanged, and T5 verifies it live on the final build.
