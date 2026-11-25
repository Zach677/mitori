//
//  AppWindowController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import AppKit

@MainActor
final class AppWindowController: NSWindowController, WindowVisibilityManaging {
    private let titleProvider: @MainActor () -> String
    private let contentProvider: @MainActor () -> NSViewController
    private let defaultSize: NSSize
    private let autosaveName: String?
    private let titleVisibility: NSWindow.TitleVisibility
    private let isResizable: Bool
    private var currentViewController: NSViewController?

    init(
        title: @escaping @MainActor () -> String,
        size: NSSize,
        autosaveName: String? = nil,
        titleVisibility: NSWindow.TitleVisibility = .hidden,
        isResizable: Bool = false,
        content: @escaping @MainActor () -> NSViewController
    ) {
        titleProvider = title
        contentProvider = content
        defaultSize = size
        self.autosaveName = autosaveName
        self.titleVisibility = titleVisibility
        self.isResizable = isResizable
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
        createdWindow.tabbingMode = .disallowed
        createdWindow.minSize = defaultSize
        createdWindow.isOpaque = true
        createdWindow.backgroundColor = .windowBackgroundColor
        createdWindow.hasShadow = true
        createdWindow.titlebarAppearsTransparent = false
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
        window.contentViewController = vc
    }
}
