# T6c — Drop the ApplePackage SPM dependency

Read `AGENTS.md` and `docs/spec.md` (§5, D-2) before starting. Preconditions:
T6b landed and its live G3 check passed.

## Goal

Remove the `Zach677/ApplePackage` package reference so the app builds from
in-repo sources only.

## Steps

1. Verify zero remaining usage: grep `Mitori/` and `MitoriTests/` for
   `import ApplePackage` and for fork-only symbols — must be empty before
   touching the project file.
2. Remove the package reference and product dependency from
   `Mitori.xcodeproj/project.pbxproj` (read the pbxproj first, per
   `AGENTS.md`; edit the `XCRemoteSwiftPackageReference` /
   `XCSwiftPackageProductDependency` entries and their listings). Update
   `Mitori.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
   accordingly (it should disappear or lose the entry after resolution).
3. `mise run clean`, then full verification.
4. `Mitori/Resources/OpenSourceLicenses.md`: keep MIT notices for ApplePackage
   (Lakr233) and ipatool (majd) — the ported code derives from them; the
   dependency being gone does not remove the attribution obligation. Drop
   notices for transitive dependencies that no longer ship (AsyncHTTPClient,
   swift-nio, ZIPFoundation, swift-collections, swift-log) if present.
5. Update `README.md` / `CHANGELOG.md`: dependency section reflects the in-repo
   `Mitori/AppleStore/` module; changelog entry under Unreleased.
6. `AGENTS.md`: update the Dependencies bullet (currently says the
   ApplePackage fork is an SPM reference) to describe `Mitori/AppleStore/`.

## Acceptance criteria

- Fresh clone + `mise run build-macos` succeeds with no network access to
  GitHub for ApplePackage (no SPM resolution of the fork).
- `mise run test-macos` green; `mise run run-macos` launches; existing
  accounts still load and refresh (stored data format untouched).
- Attribution notices present per step 4.

## Verification

- `mise run clean && mise run test-macos && mise run build-macos`, launch via
  `mise run run-macos`.

## Out of scope

- Deleting the fork repo (it stays as a read-only reference archive, D-2).
