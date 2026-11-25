//
//  MainWindowController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/25.
//

import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, WindowVisibilityManaging {
    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("dev.zach.mitori.main.toolbar")
        static let addAccount = NSToolbarItem.Identifier("main.add-account")
        static let trackingSeparator = NSToolbarItem.Identifier("main.sidebar-separator")
        static let refresh = NSToolbarItem.Identifier("main.refresh")
    }

    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let probeAppSearch: any ProbeAppSearching

    private lazy var sidebarController = AccountSidebarViewController(
        model: model,
        settings: settings
    ) { [weak self] accountID in
        self?.handleSidebarSelection(accountID)
    }

    private lazy var detailController = AccountDetailViewController(
        model: model,
        settings: settings,
        probeAppSearch: probeAppSearch
    ) { [weak self] accountID in
        self?.refreshAccount(id: accountID)
    }

    private lazy var splitViewController: NSSplitViewController = {
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 280
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 380

        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        split.splitView.setPosition(228, ofDividerAt: 0)
        return split
    }()

    private lazy var rootViewController = MainRootViewController(
        splitViewController: splitViewController,
        onAddAccount: { [weak self] in
            self?.presentAddAccountSheet()
        },
        onRetryLoad: { [weak self] in
            self?.retryLoadAccounts()
        },
        onRevealInFinder: { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.activateFileViewerSelecting([model.accountsDirectoryURL])
        }
    )

    private var selectedAccountID: String?
    private lazy var refreshToolbarButton = makeToolbarButton(
        symbolName: "arrow.clockwise",
        title: "Refresh",
        identifier: "main.refresh",
        action: #selector(handleRefreshButton)
    )
    private let refreshToolbarSpinner = NSProgressIndicator()
    private let refreshSymbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") ?? NSImage()

    init(
        model: MitoriModel,
        settings: RefreshSettingsStore,
        probeAppSearch: any ProbeAppSearching = ProbeAppSearchService()
    ) {
        self.model = model
        self.settings = settings
        self.probeAppSearch = probeAppSearch
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = ensureWindow()
        reload()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func focus() {
        guard let window else {
            show()
            return
        }
        reload()
        window.makeKeyAndOrderFront(nil)
    }

    func showAccount(id: String) {
        selectedAccountID = id
        if isVisible {
            focus()
        } else {
            show()
        }
        sidebarController.selectAccount(id: id)
        detailController.setAccountID(id)
        updateWindowChrome()
    }

    func presentAddAccountSheet() {
        if !isVisible {
            show()
        } else {
            focus()
        }
        guard let hostWindow = window else { return }

        hostWindow.presentSheet { dismiss in
            AddAccountViewController(
                model: model,
                onClose: dismiss,
                onLoginSuccess: { [weak self] accountID in
                    dismiss()
                    guard let self else { return }
                    selectedAccountID = accountID
                    reload()
                }
            )
        }
    }

    func refreshSelectedAccount() {
        guard let selectedAccountID else { return }
        refreshAccount(id: selectedAccountID)
    }

    func apply(_ change: ModelChange) {
        switch change {
        case .accounts, .loadError:
            reload()
        case let .account(accountID):
            sidebarController.reloadRow(for: accountID)
            if accountID == selectedAccountID {
                detailController.reload()
                updateWindowChrome()
            }
        case .refreshingAll:
            break
        }
    }

    func reload() {
        let accounts = model.accounts
        if let current = selectedAccountID, accounts.contains(where: { $0.id == current }) {
            // Keep selection.
        } else {
            selectedAccountID = accounts.first?.id
        }

        if let loadError = model.loadError, accounts.isEmpty {
            rootViewController.showLoadError(loadError)
        } else if accounts.isEmpty {
            rootViewController.showEmptyState()
        } else {
            rootViewController.showAccounts()
            sidebarController.reload(selecting: selectedAccountID)
            detailController.setAccountID(selectedAccountID)
        }
        // Add Account and Refresh act on the account list; the empty and error states carry their own buttons.
        window?.toolbar?.isVisible = !accounts.isEmpty
        updateWindowChrome()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.addAccount,
            ToolbarID.trackingSeparator,
            .flexibleSpace,
            ToolbarID.refresh,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarID.addAccount:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = makeToolbarButton(
                symbolName: "plus",
                title: "Add Account",
                identifier: "main.add-account",
                action: #selector(handleAddAccountButton)
            )
            item.label = "Add Account"
            return item

        case ToolbarID.trackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitViewController.splitView,
                dividerIndex: 0
            )

        case ToolbarID.refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = refreshToolbarButton
            item.label = "Refresh"
            return item

        default:
            return nil
        }
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isReleasedWhenClosed = false
        created.minSize = NSSize(width: 640, height: 420)
        created.tabbingMode = .disallowed
        created.toolbarStyle = .unified
        created.titleVisibility = .visible
        created.title = "Mitori"
        created.contentViewController = rootViewController
        // Assigning the content view controller shrinks the window to its fitting (minimum) size.
        created.setContentSize(NSSize(width: 780, height: 540))

        let toolbar = NSToolbar(identifier: ToolbarID.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        created.toolbar = toolbar

        created.center()
        // The UI fixture opens at the default size and must not touch the user's saved frame.
        if ProcessInfo.processInfo.environment["MITORI_UI_FIXTURE"] == nil {
            created.setFrameAutosaveName("dev.zach.mitori.main")
        }
        window = created
        return created
    }

    private func updateWindowChrome() {
        guard let window else { return }

        guard let account = model.account(with: selectedAccountID),
              let accountIndex = model.accounts.firstIndex(where: { $0.id == account.id })
        else {
            window.title = "Mitori"
            window.subtitle = ""
            setRefreshing(false)
            return
        }

        let presentation = AccountPresentation(
            account: account,
            accountIndex: accountIndex,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        )
        window.title = presentation.windowTitle
        window.subtitle = settings.isPersonalInformationHidden ? "" : account.storeDisplayName

        let isRefreshing: Bool = if case .refreshing = model.refreshState(for: account.id) { true } else { false }
        setRefreshing(isRefreshing)
    }

    /// A plain toolbar-bezel button sized by the toolbar itself. A custom view keeps the `main.*`
    /// accessibility identifier, which an image-only NSToolbarItem cannot carry.
    private func makeToolbarButton(symbolName: String, title: String, identifier: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(),
            target: self,
            action: action
        )
        button.bezelStyle = .toolbar
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    /// While a refresh runs, the button shows a spinner in place of its symbol and is disabled.
    private func setRefreshing(_ isRefreshing: Bool) {
        if refreshToolbarSpinner.superview == nil {
            refreshToolbarSpinner.style = .spinning
            refreshToolbarSpinner.controlSize = .small
            refreshToolbarSpinner.isDisplayedWhenStopped = false
            refreshToolbarSpinner.setAccessibilityLabel("Refreshing balance")
            refreshToolbarSpinner.setAccessibilityIdentifier("main.refresh-progress")
            refreshToolbarSpinner.translatesAutoresizingMaskIntoConstraints = false
            refreshToolbarButton.addSubview(refreshToolbarSpinner)
            NSLayoutConstraint.activate([
                refreshToolbarSpinner.centerXAnchor.constraint(equalTo: refreshToolbarButton.centerXAnchor),
                refreshToolbarSpinner.centerYAnchor.constraint(equalTo: refreshToolbarButton.centerYAnchor),
            ])
        }
        refreshToolbarButton.isEnabled = !isRefreshing
        // A blank image of the same size hides the symbol and keeps the toolbar from shifting.
        refreshToolbarButton.image = isRefreshing ? NSImage(size: refreshSymbol.size) : refreshSymbol
        if isRefreshing {
            refreshToolbarSpinner.startAnimation(nil)
        } else {
            refreshToolbarSpinner.stopAnimation(nil)
        }
    }

    private func handleSidebarSelection(_ accountID: String?) {
        selectedAccountID = accountID
        detailController.setAccountID(accountID)
        updateWindowChrome()
    }

    private func refreshAccount(id: String) {
        Task {
            await model.refreshAccount(id: id, isManualRefresh: true)
        }
    }

    private func retryLoadAccounts() {
        Task {
            await model.retryLoadAccounts()
            reload()
        }
    }

    @objc
    private func handleAddAccountButton() {
        presentAddAccountSheet()
    }

    @objc
    private func handleRefreshButton() {
        refreshSelectedAccount()
    }
}

@MainActor
private final class MainRootViewController: NSViewController {
    private let splitViewController: NSSplitViewController
    private let onAddAccount: @MainActor () -> Void
    private let onRetryLoad: @MainActor () -> Void
    private let onRevealInFinder: @MainActor () -> Void

    private let emptyStateView = NSView()
    private let loadErrorView = NSView()
    private let loadErrorMessageLabel = NSTextField(wrappingLabelWithString: "")

    init(
        splitViewController: NSSplitViewController,
        onAddAccount: @escaping @MainActor () -> Void,
        onRetryLoad: @escaping @MainActor () -> Void,
        onRevealInFinder: @escaping @MainActor () -> Void
    ) {
        self.splitViewController = splitViewController
        self.onAddAccount = onAddAccount
        self.onRetryLoad = onRetryLoad
        self.onRevealInFinder = onRevealInFinder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        addChild(splitViewController)
        let splitView = splitViewController.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        configureEmptyState()
        configureLoadErrorState()
        view.addSubview(emptyStateView)
        view.addSubview(loadErrorView)

        for subview in [splitView, emptyStateView, loadErrorView] {
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }

    func showAccounts() {
        _ = view
        splitViewController.view.isHidden = false
        emptyStateView.isHidden = true
        loadErrorView.isHidden = true
    }

    func showEmptyState() {
        _ = view
        splitViewController.view.isHidden = true
        emptyStateView.isHidden = false
        loadErrorView.isHidden = true
    }

    func showLoadError(_ message: String) {
        _ = view
        loadErrorMessageLabel.stringValue = message
        splitViewController.view.isHidden = true
        emptyStateView.isHidden = true
        loadErrorView.isHidden = false
    }

    private func configureEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true

        let iconView = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let title = NSTextField(labelWithString: "Add an Apple Account")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center
        title.setAccessibilityIdentifier("main.empty-state")

        let subtitle = NSTextField(wrappingLabelWithString: "Mitori shows the store credit of each Apple Account and keeps it in the menu bar.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true

        let addButton = NSButton(title: "Add Account…", target: self, action: #selector(addAccount))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .large
        addButton.keyEquivalent = "\r"
        addButton.setAccessibilityIdentifier("menu.empty-add-account")

        let note = NSTextField(labelWithString: "The password is saved in the Keychain on this Mac.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.alignment = .center

        let stack = NSStackView(views: [iconView, title, subtitle, addButton, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: iconView)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(12, after: addButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyStateView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
        ])
    }

    private func configureLoadErrorState() {
        loadErrorView.translatesAutoresizingMaskIntoConstraints = false
        loadErrorView.isHidden = true

        let icon = NSImageView(
            image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error") ?? NSImage()
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        icon.contentTintColor = NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange

        let title = NSTextField(labelWithString: "Couldn't Load Accounts")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        loadErrorMessageLabel.font = .systemFont(ofSize: 12)
        loadErrorMessageLabel.textColor = .secondaryLabelColor
        loadErrorMessageLabel.alignment = .center
        loadErrorMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        loadErrorMessageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true
        loadErrorMessageLabel.setAccessibilityIdentifier("main.load-error")

        let retryButton = NSButton(title: "Retry", target: self, action: #selector(retryLoad))
        retryButton.bezelStyle = .rounded
        retryButton.keyEquivalent = "\r"
        retryButton.setAccessibilityIdentifier("main.load-retry")

        let revealButton = NSButton(title: "Reveal in Finder", target: self, action: #selector(revealInFinder))
        revealButton.bezelStyle = .rounded
        revealButton.setAccessibilityIdentifier("main.load-reveal")

        let buttons = NSStackView(views: [revealButton, retryButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [icon, title, loadErrorMessageLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: loadErrorMessageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        loadErrorView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: loadErrorView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadErrorView.centerYAnchor),
        ])
    }

    @objc
    private func addAccount() {
        onAddAccount()
    }

    @objc
    private func retryLoad() {
        onRetryLoad()
    }

    @objc
    private func revealInFinder() {
        onRevealInFinder()
    }
}
