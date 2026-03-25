# Launch Halo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a brief `halo` floating prompt near the menu bar once on each cold app launch.

**Architecture:** Keep the existing SwiftUI `MenuBarExtra` and add a tiny AppKit overlay path for launch feedback. A `LaunchHaloPresenter` in the app layer owns the one-shot launch rule, while a dedicated window controller renders and dismisses the visual halo.

**Tech Stack:** SwiftUI, AppKit, Observation, Swift Testing, Tuist/mise

---

### Task 1: Add the one-shot presenter contract

**Files:**
- Modify: `Mitori/Tests/MitoriCoreTests.swift`
- Create: `Mitori/Sources/App/LaunchHaloPresenter.swift`

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test
func presentsOnlyOncePerProcess() {
    let display = LaunchHaloDisplaySpy()
    let presenter = LaunchHaloPresenter(displaying: display)

    presenter.presentIfNeeded()
    presenter.presentIfNeeded()

    #expect(display.presentCount == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test-macos --filter LaunchHaloPresenterTests`
Expected: FAIL because `LaunchHaloPresenter` and the display contract do not exist yet

- [ ] **Step 3: Write minimal implementation**

```swift
@MainActor
protocol LaunchHaloDisplaying {
    func showLaunchHalo()
}

@MainActor
final class LaunchHaloPresenter {
    private let displaying: LaunchHaloDisplaying
    private var hasPresented = false

    init(displaying: LaunchHaloDisplaying) {
        self.displaying = displaying
    }

    func presentIfNeeded() {
        guard !hasPresented else { return }
        hasPresented = true
        displaying.showLaunchHalo()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test-macos --filter LaunchHaloPresenterTests`
Expected: PASS

### Task 2: Build the launch halo overlay and wire app launch

**Files:**
- Modify: `Mitori/Sources/App/MitoriApp.swift`
- Modify: `Mitori/Sources/App/LaunchHaloPresenter.swift`
- Create: `Mitori/Sources/UI/LaunchHaloWindowController.swift`

- [ ] **Step 1: Add the live presenter path**

Create a live presenter factory that uses an AppKit-backed window controller and expose an app delegate hook for launch completion.

- [ ] **Step 2: Implement the halo window controller**

Add a borderless, non-activating floating panel that:
- positions near the menu bar on the main screen
- ignores mouse events
- hosts a SwiftUI capsule with a Messages-like icon and `halo`
- animates in, pauses about 2.2 seconds, then animates out and closes

- [ ] **Step 3: Wire launch completion**

Attach an `NSApplicationDelegateAdaptor` in `MitoriApp` so `applicationDidFinishLaunching` triggers `presentIfNeeded()`.

- [ ] **Step 4: Run focused verification**

Run: `mise run test-macos`
Expected: tests pass and the new presenter test stays green

### Task 3: Sanity-check generated project build path

**Files:**
- No source edits expected unless build feedback requires a small fix

- [ ] **Step 1: Run full repo verification**

Run: `mise run test-macos`
Expected: PASS

- [ ] **Step 2: If needed, run app build/relaunch flow**

Run: `mise run run-macos`
Expected: app rebuilds and relaunches without generation/build errors
