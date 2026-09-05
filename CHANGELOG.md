# Changelog

All notable changes to Mitori are documented in this file.

## Unreleased

- Show store credit from Apple's sign-in response so adding an account no longer requires a probe app first.
- Refresh accounts without a probe app by signing in silently, and keep probe apps as an optional background-refresh shortcut.

## 0.2.3 - 2026-09-02

- Retry temporary Apple authentication failures before asking users to sign in again.

## 0.2.2 - 2026-09-01

- Restore Apple ID sign-in after Apple began requiring signed authentication requests.
- Keep scheduled refreshes from opening Keychain authorization prompts while allowing manual refreshes to request access when needed.

## 0.2.1 - 2026-08-11

- Cancel in-flight sign-ins without saving partial account data.
- Support macOS 14 or later with compatible visual feedback on systems before macOS 26.
- Add a standard About panel with version and build information, and group privacy and legal links in Settings.
- Harden community packages with Universal binary and launch-readiness checks.

## 0.2.0 - 2026-08-08

- Add controls to open Mitori at login and hide personal account information.
- Keep zero-balance accounts visible when Apple returns an empty credit display.
- Restore reliable account row interactions with mouse, keyboard, hover, pressed, and loading states.
- Refine the menu panel and Settings layout for clearer visual hierarchy.
- Show complete Apple IDs and device IDs on hover, copy them with a click, and confirm the action with Liquid Glass feedback.

## 0.1.0 - 2026-07-29

- Monitor Apple ID store credit balances for multiple accounts from the menu bar.
- Sign in with two-factor authentication and recover expired sessions without recreating accounts.
- Refresh balances automatically with configurable intervals, lock-screen awareness, and failure backoff.
- Configure a probe app per account and localize balances using the storefront region.
- Store credentials in the macOS Keychain and keep account metadata on the local device.
- View the privacy policy and bundled third-party license terms from Settings.
- Install an ad hoc-signed Universal DMG on macOS 26 or later without an Apple Developer account.
