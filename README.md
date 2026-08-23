<p align="center">
  <img src="Mitori/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png" width="128" height="128" alt="Mitori app icon">
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

### Homebrew

```sh
brew tap Zach677/star
brew install --cask mitori
```

The Homebrew cask handles Gatekeeper quarantine for the current ad hoc-signed community build.

### Manual download

Download the latest DMG from [GitHub Releases](https://github.com/Zach677/mitori/releases/latest), then drag Mitori into `/Applications`.

Community builds are not notarized yet. If macOS blocks the first launch, open **System Settings > Privacy & Security** and choose **Open Anyway**. You can verify the downloaded files before opening them:

```sh
shasum -a 256 -c Mitori-<version>.dmg.sha256
```

## Highlights

- Check multiple Apple ID store credit balances from the menu bar.
- Sign in with two-factor authentication and recover expired sessions.
- Refresh manually or on a schedule with failure backoff and lock-screen awareness.
- Hide account names, email addresses, Apple IDs, and device IDs inside Mitori.
- Reveal complete account identifiers on hover and copy them with one click.
- Open Mitori automatically when you log in.

## Add an account

You need an Apple ID email and password, a two-factor authentication code when enabled, and the bundle ID of an app already owned by that account. Mitori generates a device identifier automatically.

The owned app acts as a balance probe. You can search for one and change it later from the account details window.

## Privacy

Mitori has no backend. Account traffic goes directly to Apple, and your data stays on your Mac.

- Development-signed builds store credentials in the macOS Data Protection Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Ad hoc community builds use the local login Keychain because Apple restricts Data Protection Keychain access to provisioned apps. Stored items do not sync through iCloud.
- Account metadata is stored at `~/Library/Application Support/Mitori/accounts.json`.
- Automatic refresh pauses while the screen is locked.

The [Privacy Policy](https://zaxh.org/mitori/privacy) is also available under **Settings > Privacy & Legal**.

## Build from source

You need macOS 14 or later, Xcode 26 or later, [mise](https://mise.jdx.dev/), `xcbeautify`, and Node.js.

```sh
brew install mise xcbeautify node

mise run build-macos
mise run run-macos
mise run test-macos
mise run test-community
mise run package-community
```

Builds are staged under `.app-build/`. Community DMGs and SHA-256 checksums are written to `dist/`.

To work in Xcode, open `Mitori.xcodeproj`.

<details>
<summary>Implementation notes</summary>

- Authentication uses [ApplePackage](https://github.com/Zach677/ApplePackage) for Apple ID login, two-factor authentication, and session management.
- Balance lookup sends a `volumeStoreDownloadProduct` request for an app owned by the account, then extracts store credit from Apple's response.
- A 60-second timer checks whether each account is due for refresh. The default interval is one hour, the minimum is 15 minutes, and failed requests back off before retrying.
- Community releases use ad hoc signing with Hardened Runtime and include both `arm64` and `x86_64` slices. The Intel build is verified but has not been tested on Intel hardware.

</details>

## Special notes

- Mitori is under early development and relies on Apple Store services that may change without notice.
- Mitori is not affiliated with or endorsed by Apple Inc. Use it only with accounts you are authorized to access and follow Apple's terms.
- Community releases are ad hoc signed and not notarized. Developer ID signing and notarization are planned.

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## Acknowledgements

Mitori uses [Zach677/ApplePackage](https://github.com/Zach677/ApplePackage), a fork of [Lakr233/ApplePackage](https://github.com/Lakr233/ApplePackage). Thanks to [Lakr Aream](https://github.com/Lakr233) for the original project and the Apple Store protocol work Mitori builds on.

## License

Mitori is available under the [MIT License](LICENSE). Resolved third-party license terms are bundled with the app and can be regenerated with `mise run scan-license`.

---

Copyright © 2026 Zach. All Rights Reserved.
