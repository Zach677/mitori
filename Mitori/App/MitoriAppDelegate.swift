//
//  MitoriAppDelegate.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import AppKit
import Combine
import Foundation

@MainActor
final class MitoriAppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    private let uiTestFixture = UITestFixture.fromEnvironment()
    private lazy var settings = uiTestFixture?.settings ?? RefreshSettingsStore()
    private lazy var model = uiTestFixture?.model ?? MitoriModel(settings: settings)
    private lazy var menuBarController = MenuBarController(
        model: model,
        settings: settings,
        probeAppSearch: uiTestFixture?.probeAppSearch ?? ProbeAppSearchService(),
        onRefreshSettingsChanged: { [weak self] in
            self?.autoRefreshScheduler.reschedule()
        }
    )
    #else
    private let settings = RefreshSettingsStore()
    private lazy var model = MitoriModel(settings: settings)
    private lazy var menuBarController = MenuBarController(
        model: model,
        settings: settings,
        onRefreshSettingsChanged: { [weak self] in
            self?.autoRefreshScheduler.reschedule()
        }
    )
    #endif
    private var schedulerChangeCancellable: AnyCancellable?
    private lazy var autoRefreshScheduler = AutoRefreshScheduler(
        nextFireDate: { [weak self] in
            self?.model.nextAutoRefreshDate()
        },
        onTick: { [weak self] in
            guard let self else { return }
            await self.model.autoRefreshTick()
        }
    )

    func applicationDidFinishLaunching(_: Notification) {
        #if DEBUG
        if let uiTestFixture {
            NSApp.mainMenu = makeMainMenu(controller: menuBarController)
            Task { @MainActor in
                try? await uiTestFixture.seed()
                await model.loadAccountsIfNeeded()
                menuBarController.presentMainWindow()
            }
            return
        }
        // A unit test host must not touch real accounts, Keychain, or the refresh timer.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApp.mainMenu = Self.makeMinimalEditMenu()
            return
        }
        #endif

        let controller = menuBarController
        NSApp.mainMenu = makeMainMenu(controller: controller)
        schedulerChangeCancellable = model.changeEvents.sink { [weak self] change in
            switch change {
            case .accounts, .account:
                self?.autoRefreshScheduler.reschedule()
            case .loadError, .refreshingAll:
                break
            }
        }

        let launchedAtLogin = Self.wasLaunchedAsLoginItem()
        Task { @MainActor in
            await model.loadAccountsIfNeeded()
            autoRefreshScheduler.start()
            if !launchedAtLogin {
                controller.presentMainWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            menuBarController.presentMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    private static func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func makeMainMenu(controller: MenuBarController) -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu(title: "Mitori")
        let about = NSMenuItem(title: "About Mitori", action: #selector(MenuBarController.openAbout), keyEquivalent: "")
        about.target = controller
        about.identifier = NSUserInterfaceItemIdentifier("menu.about")
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(MenuBarController.openSettings), keyEquivalent: ",")
        settings.target = controller
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: "Hide Mitori", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Mitori", action: #selector(MenuBarController.quit), keyEquivalent: "q")
        quit.target = controller
        appMenu.addItem(quit)

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Account menu
        let accountMenu = NSMenu(title: "Account")
        let addAccount = NSMenuItem(
            title: "Add Account…",
            action: #selector(MenuBarController.addAccount),
            keyEquivalent: "n"
        )
        addAccount.target = controller
        accountMenu.addItem(addAccount)
        accountMenu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh",
            action: #selector(MenuBarController.refreshSelectedAccount),
            keyEquivalent: "r"
        )
        refresh.target = controller
        accountMenu.addItem(refresh)

        let refreshAll = NSMenuItem(
            title: "Refresh All",
            action: #selector(MenuBarController.refreshAll),
            keyEquivalent: "R"
        )
        refreshAll.keyEquivalentModifierMask = [.command, .shift]
        refreshAll.target = controller
        accountMenu.addItem(refreshAll)
        accountMenu.addItem(.separator())

        accountMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let accountMenuItem = NSMenuItem()
        accountMenuItem.submenu = accountMenu
        mainMenu.addItem(accountMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = Self.makeEditSubmenu()
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let openMain = NSMenuItem(
            title: "Mitori",
            action: #selector(MenuBarController.openMainWindow),
            keyEquivalent: "o"
        )
        openMain.target = controller
        windowMenu.addItem(openMain)
        NSApp.windowsMenu = windowMenu

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        return mainMenu
    }

    private static func makeMinimalEditMenu() -> NSMenu {
        let editItem = NSMenuItem()
        editItem.submenu = makeEditSubmenu()
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        return mainMenu
    }

    private static func makeEditSubmenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return edit
    }
}
