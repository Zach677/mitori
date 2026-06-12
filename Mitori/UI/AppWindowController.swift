import AppKit

@MainActor
final class AppWindowController: NSWindowController, NSWindowDelegate, WindowVisibilityManaging {
    private let titleProvider: () -> String
    private let contentProvider: () -> NSViewController
    private let defaultSize: NSSize
    private let autosaveName: String?

    init(
        title: @escaping () -> String,
        size: NSSize,
        autosaveName: String? = nil,
        content: @escaping () -> NSViewController
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        createdWindow.isReleasedWhenClosed = false
        createdWindow.center()
        createdWindow.delegate = self
        createdWindow.tabbingMode = .disallowed
        createdWindow.minSize = defaultSize

        if let autosaveName {
            createdWindow.setFrameAutosaveName(autosaveName)
        }

        window = createdWindow
        return createdWindow
    }

    private func refresh(_ window: NSWindow) {
        window.title = titleProvider()
        window.contentViewController = contentProvider()
    }
}
