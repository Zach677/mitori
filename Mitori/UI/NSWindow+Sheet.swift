//
//  NSWindow+Sheet.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/25.
//

import AppKit

@MainActor
extension NSWindow {
    /// Presents a view controller as a sheet if no sheet is already attached.
    /// The dismissal closure references the sheet window weakly so closing the
    /// sheet releases both the window and its view controller.
    @discardableResult
    func presentSheet(
        makeController: (@escaping @MainActor () -> Void) -> NSViewController
    ) -> Bool {
        guard attachedSheet == nil else { return false }

        weak var presentedWindow: NSWindow?
        let dismiss: @MainActor () -> Void = { [weak self] in
            guard let self, let presentedWindow else { return }
            endSheet(presentedWindow)
        }

        let controller = makeController(dismiss)
        let sheetWindow = NSWindow(contentViewController: controller)
        sheetWindow.styleMask = [.titled]
        sheetWindow.isReleasedWhenClosed = false
        presentedWindow = sheetWindow
        beginSheet(sheetWindow) { _ in
            sheetWindow.contentViewController = nil
            sheetWindow.close()
        }
        return true
    }
}
