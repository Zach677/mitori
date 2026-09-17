# T6c - Drop the ApplePackage SPM dependency

Read `AGENTS.md` and `docs/spec.md` (§5, D-2) before starting. Preconditions:
T6b landed and its live G3 check passed.

## Goal

Remove the `Zach677/ApplePackage` package reference so the app builds from
in-repo sources only.

## Steps

1. Verify zero remaining usage: grep `Mitori/` and `MitoriTests/` for
   `import ApplePackage` and for fork-only symbols - must be empty before
   touching the project file.
2. Remove the package reference and product dependency from
   `Mitori.xcodeproj/project.pbxproj` (read the pbxproj first, per
   `AGENTS.md`; edit the `XCRemoteSwiftPackageReference` /
   `XCSwiftPackageProductDependency` entries and their listings). Update
   `Mitori.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
   accordingly (it should disappear or lose the entry after resolution).
3. `mise run clean`, then full verification.
4. `Mitori/Resources/OpenSourceLicenses.md`: keep MIT notices for ApplePackage
   (Lakr233) and ipatool (majd) - the ported code derives from them; the
   dependency being gone does not remove the attribution obligation. Drop
   notices for transitive dependencies that no longer ship (AsyncHTTPClient,
   swift-nio, ZIPFoundation, swift-collections, swift-log) if present.
   Store the ported-code notices under `Resources/AdditionalLicenses/` so
   regeneration retains them. Update `scripts/scan.license.sh` to support zero
   Swift packages when valid manual notices exist; missing expected licenses
   must still fail. It currently requires a checkout directory and a nonzero
   package count, so editing generated Markdown alone is insufficient.
5. Update `README.md` / `CHANGELOG.md`: dependency section reflects the in-repo
   `Mitori/AppleStore/` module; changelog entry under Unreleased.
6. `AGENTS.md`: update the Dependencies bullet (currently says the
   ApplePackage fork is an SPM reference) to describe `Mitori/AppleStore/`.

## Acceptance criteria

- Fresh clone + `mise run build-macos` succeeds with no network access to
  GitHub for ApplePackage (no SPM resolution of the fork).
- `mise run test-macos` green; `mise run run-macos` launches; existing
  accounts still load and refresh (stored data format untouched).
- `mise run scan-license` succeeds from the dependency-free state, keeps both
  ported-code notices, and does not restore removed transitive notices. Running
  it a second time produces the same content. Test its zero-package path and
  failure on a missing required manual notice.
- G3 and an owned-probe refresh pass after dependency removal, on the resulting
  app. An older build's success does not validate the new package.

## Verification

- G1-G6, with G4 for docs, and `mise run scan-license` as above.
- Run `mise run clean` only in the agreed implementation checkout, with no
  concurrent build. Verify a fresh source copy using the same mise tasks and
  empty project build/package caches; record its revision and resolution output.
  No global cache deletion or new worktree is required. A warm local build does
  not satisfy the fresh-source criterion.
- Rollback restores the prior package wiring and license-generation behavior
  together; stored accounts, Keychain items, and T5 safety protections stay intact.

## Out of scope

- Deleting the fork repo (it stays as a read-only reference archive, D-2).
