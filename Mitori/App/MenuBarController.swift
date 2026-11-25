//
//  MenuBarController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let privacyPolicyURL = URL(string: "https://zaxh.org/mitori/privacy")!

    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let probeAppSearch: any ProbeAppSearching
    private let onRefreshSettingsChanged: @MainActor () -> Void
    private let statusItem: NSStatusItem
    private let statusMenu = NSMenu()
    private var isStatusMenuOpen = false
    private var modelChangeCancellable: AnyCancellable?
    private var windowCloseCancellable: AnyCancellable?

    private static var usesFrameAutosave: Bool {
        ProcessInfo.processInfo.environment["MITORI_UI_FIXTURE"] == nil
    }

    private lazy var dockPolicyController = DockIconPolicyController(
        hidesWhenClosed: { [weak self] in
            self?.settings.hidesDockIconWhenClosed ?? true
        },
        hasVisibleWindow: { [weak self] in
            self?.hasAnyVisibleRegularWindow ?? false
        }
    )

    private lazy var mainWindowController = MainWindowController(
        model: model,
        settings: settings,
        probeAppSearch: probeAppSearch
    )

    private lazy var mainWindowPresenter = WindowPresentationCoordinator(window: mainWindowController)

    private lazy var settingsWindowController = AppWindowController(
        title: { "Settings" },
        size: NSSize(width: 500, height: 540),
        autosaveName: Self.usesFrameAutosave ? "dev.zach.mitori.settings" : nil,
        titleVisibility: .visible
    ) { [unowned self] in
        let vc = SettingsViewController(
            settings: settings,
            onDockIconPolicyChanged: { [weak self] in
                self?.dockPolicyController.update()
            },
            onPersonalInformationVisibilityChanged: { [weak self] in
                self?.reloadAllViews()
            },
            onRefreshSettingsChanged: { [weak self] in
                self?.onRefreshSettingsChanged()
            },
            onOpenPrivacyPolicy: {
                NSWorkspace.shared.open(Self.privacyPolicyURL)
            },
            onOpenSourceLicenses: { [weak self] in
                self?.presentDocument(.openSourceLicenses)
            }
        )
        return vc
    }

    private lazy var settingsWindowPresenter = WindowPresentationCoordinator(window: settingsWindowController)

    private var selectedDocument = BundledDocument.openSourceLicenses

    private lazy var documentWindowController = AppWindowController(
        title: { [unowned self] in selectedDocument.title },
        size: NSSize(width: 620, height: 520),
        autosaveName: Self.usesFrameAutosave ? "dev.zach.mitori.document" : nil,
        titleVisibility: .visible,
        isResizable: true
    ) { [unowned self] in
        DocumentViewController(document: selectedDocument)
    }

    private lazy var documentWindowPresenter = WindowPresentationCoordinator(window: documentWindowController)

    init(
        model: MitoriModel,
        settings: RefreshSettingsStore,
        probeAppSearch: any ProbeAppSearching = ProbeAppSearchService(),
        onRefreshSettingsChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.model = model
        self.settings = settings
        self.probeAppSearch = probeAppSearch
        self.onRefreshSettingsChanged = onRefreshSettingsChanged
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()
        configureStatusItem()
        modelChangeCancellable = model.changeEvents.sink { [weak self] change in
            self?.handleModelChange(change)
        }
        windowCloseCancellable = NotificationCenter.default
            .publisher(for: NSWindow.willCloseNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dockPolicyController.update()
                }
            }
        dockPolicyController.update()
    }

    // MARK: - Window & Menu Actions

    func presentMainWindow() {
        activateAsRegularApp()
        mainWindowPresenter.present()
        dockPolicyController.update()
    }

    func presentMainWindow(accountID: String) {
        activateAsRegularApp()
        mainWindowController.showAccount(id: accountID)
        dockPolicyController.update()
    }

    @objc
    func openMainWindow() {
        presentMainWindow()
    }

    @objc
    func addAccount() {
        activateAsRegularApp()
        mainWindowController.presentAddAccountSheet()
        dockPolicyController.update()
    }

    @objc
    func refreshSelectedAccount() {
        if mainWindowController.isVisible {
            mainWindowController.refreshSelectedAccount()
        } else {
            refreshAll()
        }
    }

    @objc
    func refreshAll() {
        Task {
            await model.refreshAll()
        }
    }

    @objc
    func openSettings() {
        activateAsRegularApp()
        settingsWindowPresenter.present()
        dockPolicyController.update()
    }

    @objc
    func openAbout() {
        activateAsRegularApp()
        NSApp.orderFrontStandardAboutPanel(nil)
        dockPolicyController.update()
    }

    @objc
    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isStatusMenuOpen = true
        rebuildStatusMenu(menu)
    }

    func menuDidClose(_: NSMenu) {
        isStatusMenuOpen = false
    }

    // MARK: - Private

    private var hasAnyVisibleRegularWindow: Bool {
        if mainWindowController.isVisible
            || settingsWindowController.isVisible
            || documentWindowController.isVisible
        {
            return true
        }
        // Include standard About panel or any other titled app window.
        return NSApp.windows.contains { window in
            window.isVisible
                && !window.isSheet
                && window.level == .normal
                && window.className != "NSStatusBarWindow"
        }
    }

    private func activateAsRegularApp() {
        dockPolicyController.ensureRegular()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureStatusItem() {
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        guard let button = statusItem.button else { return }
        if let image = NSImage(named: "MitoriStatusIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "Mitori"
            button.image = image
        } else {
            button.title = "Mitori"
        }
        button.toolTip = "Mitori"
        button.setAccessibilityIdentifier("menu.status-item")
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        let actions = StatusMenuBuilder.Actions(
            target: self,
            openAccount: #selector(handleStatusMenuAccount(_:)),
            addAccount: #selector(addAccount),
            refreshAll: #selector(refreshAll),
            openMainWindow: #selector(openMainWindow),
            openSettings: #selector(openSettings),
            quit: #selector(quit)
        )
        StatusMenuBuilder.populate(
            menu,
            accounts: model.accounts,
            loadError: model.loadError,
            isRefreshingAll: model.isRefreshingAll,
            hidesPersonalInformation: settings.isPersonalInformationHidden,
            refreshStateFor: { [model] in model.refreshState(for: $0) },
            nextAutoRefreshFor: { [model] in model.nextAutoRefreshDate(for: $0) },
            actions: actions
        )
    }

    private func presentDocument(_ document: BundledDocument) {
        selectedDocument = document
        activateAsRegularApp()
        documentWindowPresenter.present()
        dockPolicyController.update()
    }

    private func handleModelChange(_ change: ModelChange) {
        if mainWindowController.isVisible {
            mainWindowController.apply(change)
        }
        if isStatusMenuOpen {
            rebuildStatusMenu(statusMenu)
        }
    }

    private func reloadAllViews() {
        if mainWindowController.isVisible {
            mainWindowController.reload()
        }
        if isStatusMenuOpen {
            rebuildStatusMenu(statusMenu)
        }
    }

    @objc
    private func handleStatusMenuAccount(_ sender: NSMenuItem) {
        guard let accountID = sender.representedObject as? String else { return }
        presentMainWindow(accountID: accountID)
    }
}
