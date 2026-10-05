# T6c - Drop the ApplePackage SPM dependency

Read `AGENTS.md` and `docs/spec.md` §5 first. Precondition: T6b.

## Steps

1. Confirm no `import ApplePackage` or fork-only symbol remains.
2. Remove the package reference and product dependencies from
   `Mitori.xcodeproj/project.pbxproj` (read it first) and let
   `Package.resolved` lose the entry.
3. Licenses: keep the ApplePackage and ipatool MIT notices under
   `Mitori/Resources/AdditionalLicenses/` so regeneration keeps them; drop
   notices for packages that no longer ship. Update `scripts/scan.license.sh`
   to accept zero Swift packages when the manual notices exist, and still fail
   when one is missing.
4. Update README, CHANGELOG (Unreleased), and the `AGENTS.md` Dependencies bullet.

## Acceptance

1. `mise run clean && mise run build-macos` succeeds without resolving the fork.
2. `mise run scan-license` passes, is stable on a second run, and fails when a
   manual notice is removed.
3. Existing accounts load from stored data.

## Verification

G1, G2, G4, G5.
