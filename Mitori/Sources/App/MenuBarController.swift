import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let model: MitoriModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private lazy var interactionController: MenuBarInteractionController = {
        let popoverPresenter = StatusItemPopoverController(statusItem: statusItem, popover: popover)
        let contextMenuPresenter = StatusItemContextMenuPresenter(
            statusItem: statusItem,
            menuProvider: makeContextMenu
        )
        return MenuBarInteractionController(popover: popoverPresenter, contextMenu: contextMenuPresenter)
    }()

    private var detailAccountID: String?

    private lazy var addAccountWindowController = HostingWindowController(
        title: { "Add Account" },
        size: NSSize(width: 420, height: 340),
        autosaveName: "dev.zach.mitori.add-account"
    ) { [unowned self] in
        AnyView(
            AddAccountSheet(
                model: model,
                onClose: closeAddAccountWindow
            )
        )
    }

    private lazy var addAccountWindowPresenter = WindowPresentationCoordinator(window: addAccountWindowController)

    private lazy var accountDetailWindowController = HostingWindowController(
        title: { [unowned self] in
            model.account(with: detailAccountID)?.displayName ?? "Account Details"
        },
        size: NSSize(width: 440, height: 500),
        autosaveName: "dev.zach.mitori.account-detail"
    ) { [unowned self] in
        AnyView(
            AccountDetailSheet(
                model: model,
                accountID: detailAccountID ?? "",
                onClose: closeAccountDetailWindow
            )
        )
    }

    private lazy var accountDetailWindowPresenter = WindowPresentationCoordinator(window: accountDetailWindowController)

    init(model: MitoriModel) {
        self.model = model
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
        popover.contentViewController = NSHostingController(rootView: makeRootMenuBarView())
    }

    private func makeRootMenuBarView() -> RootMenuBarView {
        RootMenuBarView(
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

    private func closeAddAccountWindow() {
        addAccountWindowController.close()
    }

    private func presentAccountDetailWindow(for accountID: String) {
        detailAccountID = accountID
        popover.performClose(nil)
        accountDetailWindowPresenter.present()
    }

    private func closeAccountDetailWindow() {
        accountDetailWindowController.close()
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
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
    private func openAddAccountFromMenu(_ sender: Any?) {
        presentAddAccountWindow()
    }

    @objc
    private func refreshAllFromMenu(_ sender: Any?) {
        Task {
            await model.refreshAll()
        }
    }

    @objc
    private func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class StatusItemPopoverController: MenuBarPopoverManaging {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(statusItem: NSStatusItem, popover: NSPopover) {
        self.statusItem = statusItem
        self.popover = popover
    }

    var isPresented: Bool {
        popover.isShown
    }

    func present() {
        guard let button = statusItem.button else {
            return
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
