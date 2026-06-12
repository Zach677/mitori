import Testing

@testable import Mitori

@MainActor
struct MenuBarInteractionControllerTests {
    @Test
    func primaryClickPresentsPopoverWhenHidden() {
        let popover = PopoverSpy(isPresented: false)
        let contextMenu = ContextMenuSpy()
        let controller = MenuBarInteractionController(popover: popover, contextMenu: contextMenu)

        controller.handleClick(.primary)

        #expect(popover.events == ["present"])
        #expect(contextMenu.presentCount == 0)
    }

    @Test
    func primaryClickDismissesPopoverWhenVisible() {
        let popover = PopoverSpy(isPresented: true)
        let contextMenu = ContextMenuSpy()
        let controller = MenuBarInteractionController(popover: popover, contextMenu: contextMenu)

        controller.handleClick(.primary)

        #expect(popover.events == ["dismiss"])
        #expect(contextMenu.presentCount == 0)
    }

    @Test
    func secondaryClickDismissesPopoverBeforeShowingContextMenu() {
        let popover = PopoverSpy(isPresented: true)
        let contextMenu = ContextMenuSpy()
        let controller = MenuBarInteractionController(popover: popover, contextMenu: contextMenu)

        controller.handleClick(.secondary)

        #expect(popover.events == ["dismiss"])
        #expect(contextMenu.presentCount == 1)
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
private final class ContextMenuSpy: MenuBarContextMenuManaging {
    private(set) var presentCount = 0

    func present() {
        presentCount += 1
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
