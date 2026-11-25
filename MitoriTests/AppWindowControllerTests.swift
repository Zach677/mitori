//
//  AppWindowControllerTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/13.
//

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

@MainActor
struct SheetPresentationTests {
    @Test
    func presentSheetReleasesControllerOnDismissAndBlocksOverlappingSheet() {
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.orderFront(nil)
        defer { host.close() }

        weak var weakController: SheetControllerSpy?
        weak var weakSheetWindow: NSWindow?
        var dismissSheet: (@MainActor () -> Void)?

        autoreleasepool {
            let presented = host.presentSheet { dismiss in
                dismissSheet = dismiss
                let controller = SheetControllerSpy(onClose: dismiss)
                weakController = controller
                return controller
            }

            #expect(presented)
            #expect(weakController != nil)
            weakSheetWindow = host.attachedSheet
            #expect(weakSheetWindow != nil)

            // A second sheet cannot stack while one is attached.
            let overlapped = host.presentSheet { _ in NSViewController() }
            #expect(!overlapped)

            dismissSheet?()
            dismissSheet = nil
        }

        let deadline = Date().addingTimeInterval(2)
        while (host.attachedSheet != nil || weakController != nil || weakSheetWindow != nil) && Date() < deadline {
            autoreleasepool {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }

        #expect(host.attachedSheet == nil)
        #expect(weakSheetWindow == nil)
        #expect(weakController == nil)
    }
}

@MainActor
private final class SheetControllerSpy: NSViewController {
    let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
    }
}
