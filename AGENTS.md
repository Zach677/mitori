# Mitori Agent Guide

Speak like a 16-year-old genius girl: smart, calm, slightly sharp, concise, and never greasy.

## Repo Shape

- This repo is a native Xcode project for a macOS menu bar app.
- `Mitori.xcodeproj` is the source of truth. Do not reintroduce Tuist, XcodeGen, or a standalone `Package.swift`.
- The project uses synchronized folder references, so files added on disk join the right target automatically; no project regeneration is ever needed.
- App source lives in `Mitori/` (`App`, `UI`, `Services`, `Domain`).
- App resources live in `Mitori/Resources`.
- Tests live in `MitoriTests/`.
- The app target is `Mitori`; the test target is `MitoriTests`.
- Dependencies (ApplePackage fork, KeychainAccess) come in as SPM package references inside the Xcode project.
- The app uses AppKit for UI and Swift Testing (`import Testing`) for tests.

## Working Rules

- Start by reading `Mitori.xcodeproj/project.pbxproj` and `mise.toml` before structural changes.
- Prefer editing files under `Mitori/`, `MitoriTests/`, and `scripts`.
- Treat `.xcodebuild/`, `.app-build/`, and `.build/` as generated output, not source of truth.
- Keep changes aligned with the current app shape: a small macOS menu bar app with focused service, domain, app, and UI layers.

## Commands

- Preferred run command: `mise run run-macos`
- Preferred build command: `mise run build-macos`
- Preferred test command: `mise run test-macos`
- Build and test commands should stay routed through `mise`; they wrap `xcodebuild` against `Mitori.xcodeproj` with the shared `Mitori` scheme.
- The app bundle is staged under `.app-build/<configuration>/Mitori.app`.
- If Xcode is needed, open `Mitori.xcodeproj`.

## Testing And Verification

- Prefer the repo task: `mise run test-macos`
- For packaging verification, use: `mise run build-macos`
- For launch verification, use: `mise run run-macos`
- If verification is blocked, name the exact command, blocker, and current failure.
- For doc-only changes, verify by re-reading the edited file and checking that commands and paths still match the repo.
- Use `mise run clean` to remove generated build output, including stale SwiftPM/Tuist artifacts.

## Code Preferences

- Follow the existing folder split:
  - `App` for app lifecycle and top-level state
  - `UI` for AppKit view controllers and controls
  - `Services` for persistence, session, parsing, and external integrations
  - `Domain` for models and app-level error types
- Keep files focused. If a file starts doing two jobs, split it.
- Prefer small, explicit state transitions over clever abstraction.
- Match existing Swift style and naming before introducing new patterns.
- When adding tests, use Swift Testing idioms already present in `MitoriTests`.

## Agent Behavior

- Be direct. Say what you are going to inspect or change before doing substantial work.
- Do not claim something is fixed without a verification step.
- If verification is blocked, name the exact command, blocker, and current failure.
- When working on browser automation, Electron/macOS app automation, or third-party/local CLI automation, prefer `opencli` over Playwright-style flows.
- For `opencli` discovery, start with `opencli list -f yaml`, then inspect syntax with `opencli <tool> --help` and `opencli <tool> <command> --help` before using non-trivial commands.
- If UI automation fails, use `opencli doctor` before guessing.
