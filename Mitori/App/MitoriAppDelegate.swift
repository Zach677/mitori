import AppKit
import Foundation

@MainActor
final class MitoriAppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    private let uiTestFixture = UITestFixture.fromEnvironment()
    private lazy var settings = uiTestFixture?.settings ?? RefreshSettingsStore()
    private lazy var model = uiTestFixture?.model ?? MitoriModel(settings: settings)
    #else
    private let settings = RefreshSettingsStore()
    private lazy var model = MitoriModel(settings: settings)
    #endif
    private lazy var menuBarController = MenuBarController(model: model, settings: settings)
    private lazy var autoRefreshScheduler = AutoRefreshScheduler { [weak self] in
        guard let self else { return }
        await self.model.autoRefreshTick()
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let uiTestFixture {
            Task { @MainActor in
                try? await uiTestFixture.seed()
                _ = menuBarController
            }
            return
        }
        #endif
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
        if ProcessInfo.processInfo.environment["MITORI_OPEN_DETAIL"] == "1" {
            Task { @MainActor in
                await model.menuPresented()
                if let first = model.accounts.first {
                    menuBarController.presentAccountDetailWindowForDebugging(accountID: first.id)
                }
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
