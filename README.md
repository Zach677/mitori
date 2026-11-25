<p align="center">
  <img src="docs/assets/app-icon.png" width="128" height="128" alt="Mitori app icon">
</p>

<h1 align="center">Mitori</h1>

<p align="center">Keep an eye on Apple ID store credit from your Mac menu bar.</p>

<p align="center">
  <a href="https://github.com/Zach677/mitori/releases/latest">Download</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
  ·
  <a href="https://zaxh.org/mitori/privacy">Privacy</a>
  ·
  <a href="SECURITY.md">Security</a>
</p>

Mitori is a native macOS menu bar app for checking store credit across multiple Apple IDs. It supports two-factor authentication, automatic refresh, and session recovery without making you sign in again from scratch.

## Install

Mitori needs macOS 14 or later.

### Homebrew

```sh
brew install --cask Zach677/star/mitori
```

### Manual download

Download the latest DMG from [GitHub Releases](https://github.com/Zach677/mitori/releases/latest), then drag Mitori into `/Applications`.

Releases are signed with Developer ID and notarized by Apple. To verify a download:

```sh
shasum -a 256 -c Mitori-<version>.dmg.sha256
```

## Highlights

- Sign in with two-factor authentication and recover expired sessions.
- Refresh manually at any time, or in the background for accounts with a probe app. Background refresh never sends your password.
- Hide account names, email addresses, Apple IDs, and device IDs in the UI.
- Reveal complete account identifiers on hover and copy them with one click.
- Open Mitori automatically when you log in.

## Add an account

You need an Apple ID email and password, and a two-factor authentication code when Apple asks for one.

After sign-in, Mitori reads store credit from Apple's login response. When you refresh an account, Mitori reuses the session, or signs in again silently when needed.

You can pick an app this Apple ID already owns as a probe app. Automatic refresh needs a probe app: it checks the balance with the stored session and never sends your password. Accounts without a probe app refresh only when you ask. If the session expires, automatic refresh pauses for that account until you refresh it manually. Add or change the probe app later from the main window.

## Privacy

Mitori has no backend. Account traffic goes directly to Apple, and your data stays on your Mac.

- Credentials are stored in the macOS Data Protection Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Stored items do not sync through iCloud.
- Account metadata is stored at `~/Library/Application Support/Mitori/accounts.json`.
- Apple receives a device identifier with each sign-in and balance request. For a new account, it is the hardware address of this Mac's primary network interface.
- Automatic refresh pauses while the screen is locked.

The [Privacy Policy](https://zaxh.org/mitori/privacy) is also available under **Settings > About**.

## Build from source

You need Xcode 26 or later and [mise](https://mise.jdx.dev/). `xcbeautify` and `swiftformat` are optional for prettier build logs and header lint checks.

```sh
brew install mise

mise run build-macos
mise run run-macos
mise run test-macos
```

Builds are staged under `.app-build/`. The project signs with the maintainer's development team, so a fork must set its own `DEVELOPMENT_TEAM` in `Mitori.xcodeproj`.

To work in Xcode, open `Mitori.xcodeproj`.

<details>
<summary>Implementation notes</summary>

- Apple ID login, two-factor authentication, and session management live in `Mitori/AppleStore/`, ported from [ApplePackage](https://github.com/Zach677/ApplePackage). All Apple Store requests use one URLSession transport that validates every redirect against an Apple host allowlist. Mitori has no third-party Swift package dependencies.
- Store credit comes from Apple's sign-in response. For an account with a probe app, a refresh sends a `volumeStoreDownloadProduct` request for that app and reads store credit from the response.
- A single due-date timer wakes Mitori when the next account with a probe app is due (and on system wake or screen unlock). The default interval is one hour, the minimum is 15 minutes, and failed requests back off before retrying.
- Releases use the Hardened Runtime and include both `arm64` and `x86_64` slices. The Intel build is verified but has not been tested on Intel hardware.

</details>

## Special notes

- Mitori is under early development and relies on Apple Store services that may change without notice.
- Mitori is not affiliated with or endorsed by Apple Inc. Use it only with accounts you are authorized to access and follow Apple's terms.

See [CHANGELOG.md](CHANGELOG.md) for release notes, and [CONTRIBUTING.md](CONTRIBUTING.md) to report a bug or change the code.

## Acknowledgements

Mitori's Apple Store protocol code is ported from [Zach677/ApplePackage](https://github.com/Zach677/ApplePackage), a fork of [Lakr233/ApplePackage](https://github.com/Lakr233/ApplePackage), which adapts [ipatool](https://github.com/majd/ipatool). Thanks to [Lakr Aream](https://github.com/Lakr233) for the original project and the Apple Store protocol work Mitori builds on.

## License

Mitori is available under the [MIT License](LICENSE). Third-party license terms are bundled with the app and can be regenerated with `mise run scan-license`. Notices for ported code live in `Resources/AdditionalLicenses/`.

---

Copyright © 2026 Zach.
