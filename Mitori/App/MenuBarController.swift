import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private static let privacyPolicyURL = URL(string: "https://zaxh.org/mitori/privacy")!

    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var modelChangeCancellable: AnyCancellable?
    private lazy var menuPanelController = MenuPanelViewController(
        model: model,
        settings: settings,
        onAddAccount: { [weak self] in
            self?.presentAddAccountWindow()
        },
        onOpenAccount: { [weak self] accountID in
            self?.presentAccountDetailWindow(for: accountID)
        },
        onOpenSettings: { [weak self] in
            self?.presentSettingsWindow()
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
        return MenuBarInteractionController(popover: popoverPresenter)
    }()

    private var detailAccountID: String?
    private weak var accountDetailViewController: AccountDetailViewController?

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
            accountDetailWindowTitle
        },
        size: NSSize(width: 500, height: 400),
        autosaveName: "dev.zach.mitori.account-detail",
        windowLevel: .floating
    ) { [unowned self] in
        let accountID = detailAccountID ?? ""
        let controller = AccountDetailViewController(
            model: model,
            settings: settings,
            accountID: accountID,
            onClose: closeAccountDetailWindow,
            onProbeSaved: { [weak self] changed in
                self?.probeDidSave(accountID: accountID, probeChanged: changed)
            }
        )
        accountDetailViewController = controller
        return controller
    }

    private lazy var accountDetailWindowPresenter = WindowPresentationCoordinator(window: accountDetailWindowController)

    private lazy var settingsWindowController = AppWindowController(
        title: { "Settings" },
        size: NSSize(width: 420, height: 420),
        autosaveName: "dev.zach.mitori.settings"
    ) { [unowned self] in
        SettingsViewController(
            settings: settings,
            onPersonalInformationVisibilityChanged: { [weak self] in
                self?.reloadVisibleViews()
            },
            onOpenPrivacyPolicy: {
                NSWorkspace.shared.open(Self.privacyPolicyURL)
            },
            onOpenSourceLicenses: { [weak self] in
                self?.presentDocument(.openSourceLicenses)
            }
        )
    }

    private lazy var settingsWindowPresenter = WindowPresentationCoordinator(window: settingsWindowController)

    private var selectedDocument = BundledDocument.openSourceLicenses

    private lazy var documentWindowController = AppWindowController(
        title: { [unowned self] in selectedDocument.title },
        size: NSSize(width: 620, height: 520),
        autosaveName: "dev.zach.mitori.document"
    ) { [unowned self] in
        DocumentViewController(document: selectedDocument)
    }

    private lazy var documentWindowPresenter = WindowPresentationCoordinator(window: documentWindowController)

    init(model: MitoriModel, settings: RefreshSettingsStore) {
        self.model = model
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()
        configureStatusItem()
        configurePopover()
        modelChangeCancellable = model.changes.sink { [weak self] in
            self?.reloadVisibleViews()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(named: "MitoriStatusIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "Mitori"
            button.image = image
        } else {
            button.title = "Mitori"
        }

        button.toolTip = "Mitori"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = menuPanelController
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

    private func presentSettingsWindow() {
        popover.performClose(nil)
        settingsWindowPresenter.present()
    }

    private func presentDocument(_ document: BundledDocument) {
        selectedDocument = document
        documentWindowPresenter.present()
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

    private func probeDidSave(accountID: String, probeChanged: Bool) {
        accountDetailWindowController.close()
        presentPopover()
        guard probeChanged else { return }
        Task {
            await model.refreshAccount(id: accountID, isManualRefresh: true)
        }
    }

    private func reloadVisibleViews() {
        menuPanelController.reload()
        if accountDetailWindowController.isVisible {
            accountDetailWindowController.window?.title = accountDetailWindowTitle
            accountDetailViewController?.reload()
        }
    }

    private var accountDetailWindowTitle: String {
        guard let account = model.account(with: detailAccountID),
              let accountIndex = model.accounts.firstIndex(where: { $0.id == account.id })
        else {
            return "Account Details"
        }
        return AccountPresentation(
            account: account,
            accountIndex: accountIndex,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        ).windowTitle
    }

    @objc
    private func handleStatusItemClick(_: Any?) {
        interactionController.handleClick(clickCount: NSApp.currentEvent?.clickCount ?? 1)
    }
}

@MainActor
private final class StatusItemPopoverController: MenuBarPopoverManaging {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let beforePresent: @MainActor () -> Void

    init(
        statusItem: NSStatusItem,
        popover: NSPopover,
        beforePresent: @escaping @MainActor () -> Void
    ) {
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
