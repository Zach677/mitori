# AppleStore port record

T6a moved the ApplePackage subset that Mitori uses into `Mitori/AppleStore/`
(spec §5, D-2, D-10). This file records where each file came from.

## Source

- Repository: `Zach677/ApplePackage`, branch `zach/mitori`
- Revision: `3b535f11c83d39a302d4a4091e7eb8fb9106dc6f` (the pin in
  `Package.resolved` at the time of the port)
- License: MIT (Lakr233), with code adapted from ipatool (MIT, majd). The
  notices stay in `Mitori/Resources/OpenSourceLicenses.md`.

## File map

All paths are relative to the source repository root and this repository root.

| Source | Destination | Changes |
|--------|-------------|---------|
| `Sources/ApplePackage/Commands/Authenticate.swift` | `Mitori/AppleStore/Commands/Authenticate.swift` | none |
| `Sources/ApplePackage/Commands/Bag.swift` | `Mitori/AppleStore/Commands/Bag.swift` | none |
| `Sources/ApplePackage/Commands/Lookup.swift` | `Mitori/AppleStore/Commands/Lookup.swift` | none |
| `Sources/ApplePackage/Commands/Search.swift` | `Mitori/AppleStore/Commands/Search.swift` | none |
| `Sources/ApplePackage/Configuration/Configuration.swift` | `Mitori/AppleStore/Configuration/Configuration.swift` | `ApplePackage.` module qualifier becomes `Mitori.` |
| `Sources/ApplePackage/Configuration/Configuration+HTTPClient.swift` | `Mitori/AppleStore/Configuration/Configuration+HTTPClient.swift` | none |
| `Sources/ApplePackage/Configuration/DeviceIdentifier.swift` | `Mitori/AppleStore/Configuration/DeviceIdentifier.swift` | none |
| `Sources/ApplePackage/Models/Account.swift` | `Mitori/AppleStore/Models/Account.swift` | none |
| `Sources/ApplePackage/Models/EntityType.swift` | `Mitori/AppleStore/Models/EntityType.swift` | none |
| `Sources/ApplePackage/Models/Software.swift` | `Mitori/AppleStore/Models/Software.swift` | none |
| `Sources/ApplePackage/Supplement/Accounts.swift` | `Mitori/AppleStore/Supplement/Accounts.swift` | none |
| `Sources/ApplePackage/Supplement/AppleActionSigner.swift` | `Mitori/AppleStore/Supplement/AppleActionSigner.swift` | signer comes from the bridging header; calls `MitoriCommerceKitSign` |
| `Sources/ApplePackage/Supplement/Cookie.swift` | `Mitori/AppleStore/Supplement/Cookie.swift` | none |
| `Sources/ApplePackage/Supplement/Ensure.swift` | `Mitori/AppleStore/Supplement/Ensure.swift` | none |
| `Sources/ApplePackage/Supplement/Errors.swift` | `Mitori/AppleStore/Supplement/Errors.swift` | none |
| `Sources/ApplePackage/Supplement/Ext+Optional.swift` | `Mitori/AppleStore/Supplement/Ext+Optional.swift` | none |
| `Sources/ApplePackage/Supplement/Logger.swift` | `Mitori/AppleStore/Supplement/Logger.swift` | none |
| `Sources/ApplePackage/Supplement/MD5.swift` | `Mitori/AppleStore/Supplement/MD5.swift` | none |
| `Sources/ApplePackage/Supplement/Strings.swift` | `Mitori/AppleStore/Supplement/Strings.swift` | none |
| `Sources/ApplePackage/Supplement/Then.swift` | `Mitori/AppleStore/Supplement/Then.swift` | none |
| `Sources/CommerceKitSigner/include/CommerceKitSigner.h` | `Mitori/AppleStore/CommerceKitSigner/CommerceKitSigner.h` | `APCommerceKitSign` becomes `MitoriCommerceKitSign` |
| `Sources/CommerceKitSigner/CommerceKitSigner.m` | `Mitori/AppleStore/CommerceKitSigner/CommerceKitSigner.m` | `APCommerceKitSign` and `APCKSigningSession` get the `Mitori` prefix |
| - | `Mitori/AppleStore/Mitori-Bridging-Header.h` | new; set as `SWIFT_OBJC_BRIDGING_HEADER` of the app target |

The prefix avoids a duplicate `_APCommerceKitSign` symbol while the
ApplePackage product is still linked (until T6c).

Not ported: downloads, purchases, version lookup, IPA signature injection, the
command line tool, and their models. Mitori does not use them.

## Tests

| Source | Destination |
|--------|-------------|
| `Tests/ApplePackageTests/AccountTests.swift` | `MitoriTests/AppleStore/AppleStoreAccountTests.swift` |
| `Tests/ApplePackageTests/AuthenticateTests.swift` (offline tests only) | `MitoriTests/AppleStore/AppleStoreAuthenticateTests.swift` |
| `Tests/ApplePackageTests/ConfigurationTests.swift` | `MitoriTests/AppleStore/AppleStoreConfigurationTests.swift` |
| `Tests/ApplePackageTests/CookieTests.swift` | `MitoriTests/AppleStore/AppleStoreCookieTests.swift` |

XCTest assertions became Swift Testing expectations. Live network tests (bag,
lookup, search, login, token rotation) are not ported. The CommerceKit signer
test runs only with `APPLEPACKAGE_TEST_SAP=1`, as in the source.

## Package products

The app target links `AsyncHTTPClient`, `NIOHTTP1`, `NIOSSL`, and `Logging`
explicitly. They were transitive dependencies of ApplePackage; the resolved
versions in `Package.resolved` do not change. T6b removes AsyncHTTPClient and
NIO.
