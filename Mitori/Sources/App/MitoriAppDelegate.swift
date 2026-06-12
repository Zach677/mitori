import AppKit
import Foundation

@MainActor
final class MitoriAppDelegate: NSObject, NSApplicationDelegate {
    private let settings = RefreshSettingsStore()
    private lazy var model = MitoriModel(settings: settings)
    private lazy var menuBarController = MenuBarController(model: model, settings: settings)
    private lazy var autoRefreshScheduler = AutoRefreshScheduler { [weak self] in
        guard let self else { return }
        await self.model.autoRefreshTick()
        self.menuBarController.reloadPanel()
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = menuBarController
        autoRefreshScheduler.start()
        #if DEBUG
        if ProcessInfo.processInfo.environment["MITORI_OPEN_ADD_ACCOUNT"] == "1" {
            Task { @MainActor in
                menuBarController.presentAddAccountWindowForDebugging()
            }
        }
        if ProcessInfo.processInfo.environment["MITORI_OPEN_SETTINGS"] == "1" {
            Task { @MainActor in
                menuBarController.presentSettingsWindowForDebugging()
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
