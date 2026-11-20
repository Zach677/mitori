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
        NSApp.mainMenu = Self.makeMainMenu()
        #if DEBUG
        if let uiTestFixture {
            Task { @MainActor in
                try? await uiTestFixture.seed()
                _ = menuBarController
            }
            return
        }
        // A unit test host must not touch real accounts, Keychain, or the refresh timer.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        #endif
        _ = menuBarController
        schedulerChangeCancellable = model.changeEvents.sink { [weak self] change in
            switch change {
            case .accounts, .account:
                self?.autoRefreshScheduler.reschedule()
            case .banner, .refreshingAll:
                break
            }
        }
        autoRefreshScheduler.start()
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
