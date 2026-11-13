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
}
