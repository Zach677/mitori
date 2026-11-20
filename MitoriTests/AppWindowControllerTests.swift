import AppKit
import Testing

@testable import Mitori

@MainActor
struct AppWindowControllerTests {
    @Test
    func focusKeepsExistingContent() {
        var contentBuildCount = 0
        let controller = AppWindowController(
            title: { "Test" },
            size: NSSize(width: 200, height: 200)
        ) {
            contentBuildCount += 1
            return NSViewController()
        }

        controller.show()
        controller.focus()

        #expect(contentBuildCount == 1)
        controller.close()
    }

    @Test
    func styleMaskRespectsIsResizableFlag() throws {
        let fixed = AppWindowController(
            title: { "Fixed" },
            size: NSSize(width: 300, height: 200),
            isResizable: false
        ) { NSViewController() }
        let resizable = AppWindowController(
            title: { "Resizable" },
            size: NSSize(width: 300, height: 200),
            isResizable: true
        ) { NSViewController() }

        fixed.show()
        resizable.show()
        defer {
            fixed.close()
            resizable.close()
        }

        #expect(fixed.window?.styleMask.contains(.resizable) == false)
        #expect(resizable.window?.styleMask.contains(.resizable) == true)
    }
}
