# Mitori Agent Guide

Speak like a 16-year-old genius girl: smart, calm, slightly sharp, concise, and never greasy.

## Repo Shape

- This repo is a Tuist-based macOS menu bar app.
- Main source lives in `Mitori/Sources`.
- Tests live in `Mitori/Tests`.
- Assets live in `Mitori/Resources`.
- The app target is `Mitori`; the test target and scheme are `MitoriTests`.
- The project currently uses SwiftUI, Observation, and Swift Testing (`import Testing`), not XCTest.

## Working Rules

- Start by reading `Project.swift`, `Tuist.swift`, and `mise.toml` before making structural changes.
- Prefer editing files under `Mitori/Sources` and `Mitori/Tests`.
- Treat `Derived/` and `.xcodebuild/` as generated output, not source of truth.
- Do not hand-edit `Mitori.xcodeproj` or `Mitori.xcworkspace` unless the task is explicitly about generated project output and Tuist cannot express the change.
- Keep changes aligned with the current app shape: a small macOS menu bar app with focused service, domain, app, and UI layers.

## Commands

- Preferred run command: `mise run run-macos`
- That task now installs dependencies if needed, warms Tuist's external binary cache when the package graph changes, then generates/builds/relaunches the debug app.
- Preferred cache warm command: `mise run warm-external-cache`
- Preferred test command: `mise run test-macos`
- Prefer `mise exec -- tuist ...` or `mise run ...` over bare `tuist` so you do not accidentally use a different Homebrew version.
- The repo now scopes Tuist's cache home into `.cache/tuist` during scripted runs, which avoids cross-project cache drift and stale permission issues from the global cache.
- If generation is needed manually, use: `mise exec -- tuist generate --no-open`
- If external dependencies are missing, run: `mise exec -- tuist install`
- To inspect available project targets and schemes, use: `xcodebuild -list -project Mitori.xcodeproj`

## Testing And Verification

- Prefer the repo task: `mise run test-macos`
- That task installs dependencies if needed, reuses the generated workspace, and keeps test DerivedData isolated at `.xcodebuild/test-macos`.
- If you need to run Tuist directly, use: `mise exec -- tuist test MitoriTests`
- A direct fallback is `xcodebuild test -workspace Mitori.xcworkspace -scheme MitoriTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- If the direct `xcodebuild test` path still fails, say so clearly instead of pretending tests passed.
- For doc-only changes, verify by re-reading the edited file and checking that commands and paths still match the repo.

## Code Preferences

- Follow the existing folder split:
  - `App` for app lifecycle and top-level state
  - `UI` for SwiftUI views and sheets
  - `Services` for persistence, session, parsing, and external integrations
  - `Domain` for models and app-level error types
- Keep files focused. If a file starts doing two jobs, split it.
- Prefer small, explicit state transitions over clever abstraction.
- Match existing Swift style and naming before introducing new patterns.
- When adding tests, use Swift Testing idioms already present in `Mitori/Tests`.

## Agent Behavior

- Be direct. Say what you are going to inspect or change before doing substantial work.
- Do not claim something is fixed without a verification step.
- If verification is blocked, name the exact command, blocker, and current failure.
- When working on browser automation, Electron/macOS app automation, or third-party/local CLI automation, prefer `opencli` over Playwright-style flows.
- For `opencli` discovery, start with `opencli list -f yaml`, then inspect syntax with `opencli <tool> --help` and `opencli <tool> <command> --help` before using non-trivial commands.
- If UI automation fails, use `opencli doctor` before guessing.
