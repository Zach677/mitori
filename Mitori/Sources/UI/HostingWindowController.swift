import AppKit
import SwiftUI

@MainActor
final class HostingWindowController: NSWindowController, NSWindowDelegate, WindowVisibilityManaging {
    private let titleProvider: () -> String
    private let contentProvider: () -> AnyView
    private let defaultSize: NSSize
    private let autosaveName: String?

    init(
        title: @escaping () -> String,
        size: NSSize,
        autosaveName: String? = nil,
        content: @escaping () -> AnyView
    ) {
        titleProvider = title
        contentProvider = content
        defaultSize = size
        self.autosaveName = autosaveName
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = ensureWindow()
        refresh(window)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func focus() {
        guard let window else {
            show()
            return
        }

        refresh(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let createdWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdWindow.isReleasedWhenClosed = false
        createdWindow.center()
        createdWindow.delegate = self
        createdWindow.tabbingMode = .disallowed

        if let autosaveName {
            createdWindow.setFrameAutosaveName(autosaveName)
        }

        window = createdWindow
        return createdWindow
    }

    private func refresh(_ window: NSWindow) {
        window.title = titleProvider()

        if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = contentProvider()
        } else {
            let hostingController = NSHostingController(rootView: contentProvider())
            // Let the window track SwiftUI's intrinsic content size so content drives
            // the window dimensions instead of getting clipped or scrolled inside a
            // fixed frame.
            hostingController.sizingOptions = [.intrinsicContentSize]
            window.contentViewController = hostingController
        }
    }
}
