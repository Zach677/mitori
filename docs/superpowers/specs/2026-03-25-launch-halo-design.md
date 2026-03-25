# Launch Halo Design

**Date:** 2026-03-25

**Goal:** Make each cold launch feel visibly alive by showing a brief, menu-bar-adjacent `halo` prompt without stealing focus.

## User Experience

- On every cold launch, show a small floating prompt near the macOS menu bar.
- The prompt uses a Messages-like bubble icon plus the text `halo`.
- The prompt fades and scales in, remains visible for about 2.2 seconds, then fades out and drifts slightly upward.
- The prompt does not take focus, does not block clicks, and does not require the user to open the menu manually.
- The prompt is shown once per process launch only.

## Constraints

- Keep the existing `MenuBarExtra` app structure.
- Avoid notifications because they require separate platform behavior and can feel heavier than the requested effect.
- Avoid converting the whole menu bar implementation to a custom `NSStatusItem`; that would be disproportionate for this feature.

## Architecture

- Add a small launch-halo presenter in the `App` layer that guarantees single-fire behavior for the current process.
- Add an AppKit-backed floating overlay window that can host a SwiftUI halo view.
- Trigger the presenter from `MitoriApp` when the app finishes launching.
- Keep animation and copy in the halo view/controller so the main model stays focused on account/session state.

## Testing

- Add a focused test for presenter behavior: first trigger fires, later triggers in the same process do nothing.
- Keep AppKit window layout outside unit-test scope; verify that part with the repo build/test pass.

## Files

- Modify `Mitori/Sources/App/MitoriApp.swift`
- Add `Mitori/Sources/App/LaunchHaloPresenter.swift`
- Add `Mitori/Sources/UI/LaunchHaloWindowController.swift`
- Add `Mitori/Tests/MitoriCoreTests.swift`
