import AppKit
import Foundation

@MainActor
final class MitoriAppDelegate: NSObject, NSApplicationDelegate {
    private let model = MitoriModel()
    private lazy var menuBarController = MenuBarController(model: model)

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = menuBarController
        #if DEBUG
        if ProcessInfo.processInfo.environment["MITORI_OPEN_ADD_ACCOUNT"] == "1" {
            Task { @MainActor in
                menuBarController.presentAddAccountWindowForDebugging()
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
