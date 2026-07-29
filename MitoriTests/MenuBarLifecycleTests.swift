import Testing

@testable import Mitori

@MainActor
struct MenuBarInteractionControllerTests {
    @Test
    func primaryClickPresentsPopoverWhenHidden() {
        let popover = PopoverSpy(isPresented: false)
        let controller = MenuBarInteractionController(popover: popover)

        controller.handleClick(clickCount: 1)

        #expect(popover.events == ["present"])
    }

    @Test
    func primaryClickDismissesPopoverWhenVisible() {
        let popover = PopoverSpy(isPresented: true)
        let controller = MenuBarInteractionController(popover: popover)

        controller.handleClick(clickCount: 1)

        #expect(popover.events == ["dismiss"])
    }

    @Test
    func repeatedClickLeavesPopoverStateUnchanged() {
        let popover = PopoverSpy(isPresented: false)
        let controller = MenuBarInteractionController(popover: popover)

        controller.handleClick(clickCount: 2)

        #expect(popover.events.isEmpty)
    }
}

@MainActor
struct WindowPresentationCoordinatorTests {
    @Test
    func firstPresentationShowsWindow() {
        let window = WindowSpy(isVisible: false)
        let coordinator = WindowPresentationCoordinator(window: window)

        coordinator.present()

        #expect(window.showCount == 1)
        #expect(window.focusCount == 0)
    }

    @Test
    func repeatedPresentationFocusesExistingWindow() {
        let window = WindowSpy(isVisible: true)
        let coordinator = WindowPresentationCoordinator(window: window)

        coordinator.present()

        #expect(window.showCount == 0)
        #expect(window.focusCount == 1)
    }
}

@MainActor
private final class PopoverSpy: MenuBarPopoverManaging {
    var isPresented: Bool
    private(set) var events: [String] = []

    init(isPresented: Bool) {
        self.isPresented = isPresented
    }

    func present() {
        events.append("present")
        isPresented = true
    }

    func dismiss() {
        events.append("dismiss")
        isPresented = false
    }
}

@MainActor
private final class WindowSpy: WindowVisibilityManaging {
    var isVisible: Bool
    private(set) var showCount = 0
    private(set) var focusCount = 0

    init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    func show() {
        showCount += 1
        isVisible = true
    }

    func focus() {
        focusCount += 1
    }
}
