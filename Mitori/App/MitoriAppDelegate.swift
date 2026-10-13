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
        NSApp.mainMenu = Self.makeMainMenu()
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

    /// An accessory app shows no menu bar, but text fields still need the Edit
    /// menu key equivalents for paste, copy, select all, and undo.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = edit
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        return mainMenu
    }
}
