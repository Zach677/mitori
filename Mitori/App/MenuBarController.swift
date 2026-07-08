import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private lazy var menuPanelController = MenuPanelViewController(
        model: model,
        onAddAccount: { [weak self] in
            self?.presentAddAccountWindow()
        },
        onOpenAccount: { [weak self] accountID in
            self?.presentAccountDetailWindow(for: accountID)
        },
        onQuit: {
            NSApp.terminate(nil)
        }
    )
    private lazy var interactionController: MenuBarInteractionController = {
        let popoverPresenter = StatusItemPopoverController(
            statusItem: statusItem,
            popover: popover,
            beforePresent: { [weak self] in
                self?.menuPanelController.prepareForPresentation()
            }
        )
        let contextMenuPresenter = StatusItemContextMenuPresenter(
            statusItem: statusItem,
            menuProvider: makeContextMenu
        )
        return MenuBarInteractionController(popover: popoverPresenter, contextMenu: contextMenuPresenter)
    }()

    private var detailAccountID: String?

    private lazy var addAccountWindowController = AppWindowController(
        title: { "Add Account" },
        size: NSSize(width: 430, height: 430),
        autosaveName: "dev.zach.mitori.add-account",
        windowLevel: .floating
    ) { [unowned self] in
        AddAccountViewController(
            model: model,
            onClose: closeAddAccountWindow,
            onLoginSuccess: { [weak self] accountID in
                self?.addAccountDidSucceed(accountID: accountID)
            }
        )
    }

    private lazy var addAccountWindowPresenter = WindowPresentationCoordinator(window: addAccountWindowController)

    private lazy var accountDetailWindowController = AppWindowController(
        title: { [unowned self] in
            model.account(with: detailAccountID)?.displayName ?? "Account Details"
        },
        size: NSSize(width: 500, height: 400),
        autosaveName: "dev.zach.mitori.account-detail",
        windowLevel: .floating
    ) { [unowned self] in
        AccountDetailViewController(
            model: model,
            accountID: detailAccountID ?? "",
            onClose: closeAccountDetailWindow,
            onProbeSaved: { [weak self] changed in self?.probeDidSave(probeChanged: changed) }
        )
    }

    private lazy var accountDetailWindowPresenter = WindowPresentationCoordinator(window: accountDetailWindowController)

    private lazy var settingsWindowController = AppWindowController(
        title: { "Settings" },
        size: NSSize(width: 380, height: 190),
        autosaveName: "dev.zach.mitori.settings"
    ) { [unowned self] in
        SettingsViewController(settings: settings)
    }

    private lazy var settingsWindowPresenter = WindowPresentationCoordinator(window: settingsWindowController)

    init(model: MitoriModel, settings: RefreshSettingsStore) {
        self.model = model
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()
        configureStatusItem()
        configurePopover()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(
            systemSymbolName: "creditcard.and.123",
            accessibilityDescription: "Mitori"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "Mitori"
        }

        button.toolTip = "Mitori"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = menuPanelController
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let addAccountItem = NSMenuItem(
            title: "Add Account",
            action: #selector(openAddAccountFromMenu(_:)),
            keyEquivalent: ""
        )
        addAccountItem.target = self
        menu.addItem(addAccountItem)

        let refreshItem = NSMenuItem(
            title: "Refresh All",
            action: #selector(refreshAllFromMenu(_:)),
            keyEquivalent: ""
        )
        refreshItem.target = self
        refreshItem.isEnabled = !model.accounts.isEmpty && !model.isRefreshingAll
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Mitori",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func presentAddAccountWindow() {
        popover.performClose(nil)
        addAccountWindowPresenter.present()
    }

    #if DEBUG
    func presentAddAccountWindowForDebugging() {
        presentAddAccountWindow()
    }

    func presentSettingsWindowForDebugging() {
        presentSettingsWindow()
    }

    func presentAccountDetailWindowForDebugging(accountID: String) {
        presentAccountDetailWindow(for: accountID)
    }
    #endif

    private func closeAddAccountWindow() {
        addAccountWindowController.close()
        menuPanelController.reload()
    }

    private func addAccountDidSucceed(accountID: String) {
        addAccountWindowController.close()
        presentAccountDetailWindow(for: accountID)
    }

    func reloadPanel() {
        menuPanelController.reload()
    }

    private func presentSettingsWindow() {
        popover.performClose(nil)
        settingsWindowPresenter.present()
    }

    private func presentAccountDetailWindow(for accountID: String) {
        detailAccountID = accountID
        popover.performClose(nil)
        accountDetailWindowPresenter.present()
    }

    private func presentPopover() {
        menuPanelController.reload()
        guard let button = statusItem.button else { return }
        menuPanelController.prepareForPresentation()
        if let preferredContentSize = popover.contentViewController?.preferredContentSize,
           preferredContentSize != .zero {
            popover.contentSize = preferredContentSize
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closeAccountDetailWindow() {
        accountDetailWindowController.close()
        presentPopover()
    }

    private func probeDidSave(probeChanged: Bool) {
        let accountID = detailAccountID
        accountDetailWindowController.close()
        if probeChanged, let accountID { model.startRefresh(accountID: accountID) }
        presentPopover()
        guard probeChanged, let accountID else { return }
        Task {
            await model.refreshAccount(id: accountID, isManualRefresh: true)
            menuPanelController.reload()
        }
    }

    @objc
    private func handleStatusItemClick(_: Any?) {
        let clickKind: StatusItemClickKind
        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            clickKind = .secondary
        default:
            clickKind = .primary
        }

        interactionController.handleClick(clickKind)
    }

    @objc
    private func openAddAccountFromMenu(_: Any?) {
        presentAddAccountWindow()
    }

    @objc
    private func openSettingsFromMenu(_: Any?) {
        presentSettingsWindow()
    }

    @objc
    private func refreshAllFromMenu(_: Any?) {
        Task {
            await model.refreshAll()
            menuPanelController.reload()
        }
    }

    @objc
    private func quitFromMenu(_: Any?) {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class StatusItemPopoverController: MenuBarPopoverManaging {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let beforePresent: () -> Void

    init(statusItem: NSStatusItem, popover: NSPopover, beforePresent: @escaping () -> Void) {
        self.statusItem = statusItem
        self.popover = popover
        self.beforePresent = beforePresent
    }

    var isPresented: Bool {
        popover.isShown
    }

    func present() {
        guard let button = statusItem.button else {
            return
        }

        beforePresent()
        if let preferredContentSize = popover.contentViewController?.preferredContentSize,
           preferredContentSize != .zero {
            popover.contentSize = preferredContentSize
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func dismiss() {
        popover.performClose(nil)
    }
}

@MainActor
private final class StatusItemContextMenuPresenter: MenuBarContextMenuManaging {
    private let statusItem: NSStatusItem
    private let menuProvider: () -> NSMenu

    init(statusItem: NSStatusItem, menuProvider: @escaping () -> NSMenu) {
        self.statusItem = statusItem
        self.menuProvider = menuProvider
    }

    func present() {
        guard let button = statusItem.button else {
            return
        }

        menuProvider().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }
}
