import AppKit

@MainActor
final class AppWindowController: NSWindowController, NSWindowDelegate, WindowVisibilityManaging {
    private let titleProvider: @MainActor () -> String
    private let contentProvider: @MainActor () -> NSViewController
    private let defaultSize: NSSize
    private let autosaveName: String?
    private let windowLevel: NSWindow.Level
    private var currentViewController: NSViewController?

    init(
        title: @escaping @MainActor () -> String,
        size: NSSize,
        autosaveName: String? = nil,
        windowLevel: NSWindow.Level = .normal,
        content: @escaping @MainActor () -> NSViewController
    ) {
        titleProvider = title
        contentProvider = content
        defaultSize = size
        self.autosaveName = autosaveName
        self.windowLevel = windowLevel
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdWindow.isReleasedWhenClosed = false
        createdWindow.center()
        createdWindow.delegate = self
        createdWindow.tabbingMode = .disallowed
        createdWindow.minSize = defaultSize
        createdWindow.level = windowLevel
        createdWindow.isOpaque = false
        createdWindow.backgroundColor = .clear
        createdWindow.hasShadow = true
        createdWindow.titlebarAppearsTransparent = true
        createdWindow.titleVisibility = .hidden

        if let autosaveName {
            createdWindow.setFrameAutosaveName(autosaveName)
        }
        createdWindow.setContentSize(defaultSize)

        window = createdWindow
        return createdWindow
    }

    private func refresh(_ window: NSWindow) {
        window.title = titleProvider()
        let vc = contentProvider()
        currentViewController = vc
        let glass = NSGlassEffectView()
        glass.contentView = vc.view
        window.contentView = glass
    }
}
