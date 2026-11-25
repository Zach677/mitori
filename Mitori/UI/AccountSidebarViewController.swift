//
//  AccountSidebarViewController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/25.
//

import AppKit

@MainActor
final class AccountSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let rowCellIdentifier = NSUserInterfaceItemIdentifier("AccountSidebarCell")

    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let onSelectAccount: @MainActor (String?) -> Void

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var accounts: [StoredAccountMeta] = []
    private var selectedAccountID: String?
    private var isSuppressingSelectionCallback = false

    init(
        model: MitoriModel,
        settings: RefreshSettingsStore,
        onSelectAccount: @escaping @MainActor (String?) -> Void
    ) {
        self.model = model
        self.settings = settings
        self.onSelectAccount = onSelectAccount
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        configureTableView()
        reload(selecting: selectedAccountID)
    }

    func reload(selecting preferredID: String? = nil) {
        accounts = model.accounts
        let nextSelection: String? = if let preferredID, accounts.contains(where: { $0.id == preferredID }) {
            preferredID
        } else if let current = selectedAccountID, accounts.contains(where: { $0.id == current }) {
            current
        } else {
            accounts.first?.id
        }
        selectedAccountID = nextSelection

        guard isViewLoaded else { return }

        isSuppressingSelectionCallback = true
        tableView.reloadData()
        if let nextSelection, let row = accounts.firstIndex(where: { $0.id == nextSelection }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        isSuppressingSelectionCallback = false
    }

    func selectAccount(id: String) {
        selectedAccountID = id
        guard isViewLoaded, let row = accounts.firstIndex(where: { $0.id == id }) else { return }
        isSuppressingSelectionCallback = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isSuppressingSelectionCallback = false
    }

    func reloadRow(for accountID: String) {
        accounts = model.accounts
        guard isViewLoaded, let row = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in _: NSTableView) -> Int {
        accounts.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard accounts.indices.contains(row) else { return nil }
        let account = accounts[row]
        let presentation = AccountPresentation(
            account: account,
            accountIndex: row,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        )
        let refreshState = model.refreshState(for: account.id)
        let issue = AccountIssuePresentation(
            account: account,
            nextAutoRefreshAt: model.nextAutoRefreshDate(for: account.id)
        )

        let cell = (tableView.makeView(withIdentifier: Self.rowCellIdentifier, owner: self) as? AccountSidebarCellView)
            ?? AccountSidebarCellView(identifier: Self.rowCellIdentifier)
        cell.configure(
            account: account,
            presentation: presentation,
            refreshState: refreshState,
            issue: issue
        )
        return cell
    }

    func tableView(_: NSTableView, heightOfRow _: Int) -> CGFloat {
        44
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isSuppressingSelectionCallback else { return }
        let row = tableView.selectedRow
        let newID = accounts.indices.contains(row) ? accounts[row].id : nil
        guard newID != selectedAccountID else { return }
        selectedAccountID = newID
        onSelectAccount(newID)
    }

    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AccountColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .custom
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.floatsGroupRows = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("main.sidebar")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

@MainActor
final class AccountSidebarCellView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let balanceLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var defaultSubtitleColor: NSColor = .secondaryLabelColor

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            applyForegroundColors()
        }
    }

    func configure(
        account: StoredAccountMeta,
        presentation: AccountPresentation,
        refreshState: RefreshState,
        issue: AccountIssuePresentation?
    ) {
        nameLabel.stringValue = presentation.name
        let balanceText = account.balanceDisplayText ?? "—"
        balanceLabel.stringValue = balanceText

        let isRefreshing: Bool = if case .refreshing = refreshState { true } else { false }
        let hint: String?
        if isRefreshing {
            subtitleLabel.stringValue = "Refreshing…"
            defaultSubtitleColor = .secondaryLabelColor
            hint = "Refreshing"
        } else if let sidebarHint = issue?.sidebarHint {
            subtitleLabel.stringValue = sidebarHint
            defaultSubtitleColor = issue?.tintColor ?? .secondaryLabelColor
            hint = sidebarHint
        } else {
            subtitleLabel.stringValue = account.storeDisplayName
            defaultSubtitleColor = .secondaryLabelColor
            hint = nil
        }

        applyForegroundColors()

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("account-row.\(account.id)")
        setAccessibilityLabel(presentation.name)
        setAccessibilityValue([account.balanceDisplayText ?? "No balance", hint].compactMap { $0 }.joined(separator: ", "))
    }

    private func configureLayout() {
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        nameLabel.alignment = .left
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        balanceLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        balanceLabel.alignment = .right
        balanceLabel.lineBreakMode = .byClipping
        balanceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        balanceLabel.setContentHuggingPriority(.required, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.alignment = .left
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [nameLabel, balanceLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 8
        topRow.distribution = .fill
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [topRow, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func applyForegroundColors() {
        // Custom blended warning/error colors do not auto-invert on emphasized sourceList rows.
        if backgroundStyle == .emphasized {
            nameLabel.textColor = .alternateSelectedControlTextColor
            balanceLabel.textColor = .alternateSelectedControlTextColor
            subtitleLabel.textColor = NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85)
        } else {
            nameLabel.textColor = .labelColor
            balanceLabel.textColor = .secondaryLabelColor
            subtitleLabel.textColor = defaultSubtitleColor
        }
    }
}
