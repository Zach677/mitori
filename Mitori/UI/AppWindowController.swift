//
//  AppWindowController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import AppKit

@MainActor
final class AppWindowController: NSWindowController, NSWindowDelegate, WindowVisibilityManaging {
    private let titleProvider: @MainActor () -> String
    private let contentProvider: @MainActor () -> NSViewController
    private let defaultSize: NSSize
    private let autosaveName: String?
    private let windowLevel: NSWindow.Level
    private let titleVisibility: NSWindow.TitleVisibility
    private let isResizable: Bool
    private let onWindowClose: @MainActor () -> Void
    private var currentViewController: NSViewController?

    init(
        title: @escaping @MainActor () -> String,
        size: NSSize,
        autosaveName: String? = nil,
        windowLevel: NSWindow.Level = .normal,
        titleVisibility: NSWindow.TitleVisibility = .hidden,
        isResizable: Bool = false,
        onWindowClose: @escaping @MainActor () -> Void = {},
        content: @escaping @MainActor () -> NSViewController
    ) {
        titleProvider = title
        contentProvider = content
        defaultSize = size
        self.autosaveName = autosaveName
        self.windowLevel = windowLevel
        self.titleVisibility = titleVisibility
        self.isResizable = isResizable
        self.onWindowClose = onWindowClose
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

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        onWindowClose()
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if isResizable {
            styleMask.insert(.resizable)
        }
        let createdWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: styleMask,
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
        createdWindow.titleVisibility = titleVisibility

        createdWindow.setContentSize(defaultSize)
        if let autosaveName {
            createdWindow.setFrameAutosaveName(autosaveName)
        }

        window = createdWindow
        return createdWindow
    }

    private func refresh(_ window: NSWindow) {
        window.title = titleProvider()
        let vc = contentProvider()
        currentViewController = vc
        if #available(macOS 26.0, *) {
            window.backgroundColor = .clear
            let glass = NSGlassEffectView()
            glass.contentView = vc.view
            window.contentView = glass
        } else {
            window.backgroundColor = .windowBackgroundColor
            window.contentView = vc.view
        }
    }
}
