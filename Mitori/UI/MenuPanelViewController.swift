import AppKit

@MainActor
final class MenuPanelViewController: NSViewController {
    private enum Metrics {
        static let width: CGFloat = 360
        static let maxScrollHeight: CGFloat = 420
    }

    private let model: MitoriModel
    private let onAddAccount: () -> Void
    private let onOpenAccount: (String) -> Void
    private let onQuit: () -> Void

    private let contentStack = NSStackView()
    private let accountsStack = NSStackView()
    private let accountScrollView = NSScrollView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private var accountScrollHeightConstraint: NSLayoutConstraint?

    init(
        model: MitoriModel,
        onAddAccount: @escaping () -> Void,
        onOpenAccount: @escaping (String) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.onAddAccount = onAddAccount
        self.onOpenAccount = onOpenAccount
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Metrics.width).isActive = true
        configureLayout()
        reload()
    }

    func prepareForPresentation() {
        reload()
        Task {
            await model.menuPresented()
            reload()
        }
    }

    func reload() {
        guard isViewLoaded else { return }

        refreshButton.isEnabled = !model.accounts.isEmpty && !model.isRefreshingAll
        reloadAccounts()
        reloadBanner()
        reloadSummary()
        updatePanelSize()
    }
}

private extension MenuPanelViewController {
    func configureLayout() {
        contentStack.orientation = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(configureAccountScrollView())

        bannerLabel.font = .systemFont(ofSize: 11)
        bannerLabel.textColor = .secondaryLabelColor
        bannerLabel.lineBreakMode = .byWordWrapping
        bannerLabel.maximumNumberOfLines = 2
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(wrapped(bannerLabel, horizontal: 16, vertical: 4))

        contentStack.addArrangedSubview(makeFooter())
    }

    func makeHeader() -> NSView {
        let wrapper = NSView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "creditcard.and.123", accessibilityDescription: "Mitori")
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "Mitori")
        title.font = .systemFont(ofSize: 14, weight: .medium)

        let titleStack = NSStackView(views: [icon, title])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh All")
        refreshButton.imagePosition = .imageOnly
        refreshButton.isBordered = false
        refreshButton.controlSize = .small
        refreshButton.focusRingType = .none
        refreshButton.target = self
        refreshButton.action = #selector(refreshAll)
        refreshButton.toolTip = "Refresh All"

        let addButton = NSButton()
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Account")
        addButton.imagePosition = .imageOnly
        addButton.isBordered = false
        addButton.controlSize = .small
        addButton.focusRingType = .none
        addButton.target = self
        addButton.action = #selector(addAccount)
        addButton.toolTip = "Add Account"

        stack.addArrangedSubview(titleStack)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(refreshButton)
        stack.addArrangedSubview(addButton)

        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10),
            refreshButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.widthAnchor.constraint(equalToConstant: 28),
        ])

        return wrapper
    }

    func configureAccountScrollView() -> NSView {
        accountsStack.orientation = .vertical
        accountsStack.alignment = .width
        accountsStack.spacing = 8
        accountsStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        accountsStack.translatesAutoresizingMaskIntoConstraints = true

        accountScrollView.hasVerticalScroller = false
        accountScrollView.drawsBackground = false
        accountScrollView.borderType = .noBorder
        accountScrollView.documentView = accountsStack
        accountScrollView.translatesAutoresizingMaskIntoConstraints = false

        let heightConstraint = accountScrollView.heightAnchor.constraint(equalToConstant: 120)
        heightConstraint.isActive = true
        accountScrollHeightConstraint = heightConstraint

        return accountScrollView
    }

    func makeFooter() -> NSView {
        let wrapper = NSView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .tertiaryLabelColor

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quit))
        quitButton.bezelStyle = .inline
        quitButton.font = .systemFont(ofSize: 11)

        stack.addArrangedSubview(summaryLabel)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(quitButton)

        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10),
        ])

        return wrapper
    }

    func reloadAccounts() {
        accountsStack.arrangedSubviews.forEach { view in
            accountsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if model.accounts.isEmpty {
            accountsStack.addArrangedSubview(makeEmptyState())
            updateAccountDocumentFrame()
            return
        }

        for account in model.accounts {
            accountsStack.addArrangedSubview(AccountRowView(
                account: account,
                refreshState: model.refreshState(for: account.id),
                onOpen: { [weak self] in
                    self?.onOpenAccount(account.id)
                },
                onRefresh: { [weak self] in
                    self?.refreshAccount(account.id)
                }
            ))
        }
        updateAccountDocumentFrame()
    }

    func makeEmptyState() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 12, bottom: 24, right: 12)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 30, weight: .light)
        icon.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: "No accounts yet")
        title.font = .systemFont(ofSize: 13, weight: .medium)

        let subtitle = NSTextField(labelWithString: "Add an Apple ID to start tracking balances.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let button = NSButton(title: "Add Account", target: self, action: #selector(addAccount))
        button.bezelStyle = .rounded
        button.controlSize = .small

        [icon, title, subtitle, button].forEach(stack.addArrangedSubview(_:))
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.48).cgColor
        stack.layer?.cornerRadius = 8
        stack.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        stack.layer?.borderWidth = 0.5
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.width - 24).isActive = true
        return stack
    }

    func reloadBanner() {
        let message = model.bannerMessage ?? ""
        bannerLabel.stringValue = message
        bannerLabel.isHidden = message.isEmpty
    }

    func reloadSummary() {
        let count = model.accounts.count
        guard count > 0 else {
            summaryLabel.stringValue = ""
            return
        }

        let refreshedAt = model.accounts.compactMap(\.lastRefreshAt).max()
        let refreshLabel = refreshedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never"
        summaryLabel.stringValue = "\(count) account\(count == 1 ? "" : "s") · \(refreshLabel)"
    }

    func updateAccountDocumentFrame() {
        let documentWidth = Metrics.width
        let fittingHeight = accountsStack.fittingSize.height
        let minimumHeight: CGFloat = model.accounts.isEmpty ? 116 : 0
        let visibleHeight = min(max(fittingHeight, minimumHeight), Metrics.maxScrollHeight)
        accountsStack.frame = NSRect(x: 0, y: 0, width: documentWidth, height: fittingHeight)
        accountScrollView.hasVerticalScroller = fittingHeight > Metrics.maxScrollHeight
        accountScrollHeightConstraint?.constant = visibleHeight
    }

    func updatePanelSize() {
        view.layoutSubtreeIfNeeded()
        let height = min(max(contentStack.fittingSize.height, 180), 560)
        preferredContentSize = NSSize(width: Metrics.width, height: height)
    }

    func wrapped(_ view: NSView, horizontal: CGFloat, vertical: CGFloat) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: horizontal),
            view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -horizontal),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: vertical),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -vertical),
        ])
        return wrapper
    }

    @objc
    func addAccount() {
        onAddAccount()
    }

    @objc
    func refreshAll() {
        Task {
            await model.refreshAll()
            reload()
        }
    }

    @objc
    func quit() {
        onQuit()
    }

    func refreshAccount(_ accountID: String) {
        Task {
            await model.refreshAccount(id: accountID, isManualRefresh: true)
            reload()
        }
    }
}

@MainActor
private final class AccountRowView: NSView {
    private let account: StoredAccountMeta
    private let refreshState: RefreshState
    private let onOpen: () -> Void
    private let onRefresh: () -> Void

    init(
        account: StoredAccountMeta,
        refreshState: RefreshState,
        onOpen: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.account = account
        self.refreshState = refreshState
        self.onOpen = onOpen
        self.onRefresh = onRefresh
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.58).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        layer?.borderWidth = 0.5

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8

        let avatar = makeAvatar()
        let identity = NSStackView()
        identity.orientation = .vertical
        identity.spacing = 1
        identity.addArrangedSubview(label(account.displayName, size: 12, weight: .medium))
        identity.addArrangedSubview(label(account.email, size: 11, color: .secondaryLabelColor))

        let status = label(statusTitle, size: 11, weight: .medium, color: statusTint)
        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        chevron.contentTintColor = .tertiaryLabelColor
        top.addArrangedSubview(avatar)
        top.addArrangedSubview(identity)
        top.addArrangedSubview(NSView())
        top.addArrangedSubview(status)
        top.addArrangedSubview(chevron)

        let divider = NSBox()
        divider.boxType = .separator

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8

        let balanceStack = NSStackView()
        balanceStack.orientation = .vertical
        balanceStack.spacing = 2
        balanceStack.addArrangedSubview(label(
            account.balanceSnapshot?.displayText ?? "-",
            size: 21,
            weight: .medium,
            color: .labelColor,
            monospaced: true
        ))
        if !account.regionLabel.isEmpty {
            balanceStack.addArrangedSubview(label(account.regionLabel, size: 11, color: .tertiaryLabelColor))
        }

        let button = NSButton(
            title: account.requiresProbeConfiguration ? "Configure" : "",
            target: self,
            action: #selector(refresh)
        )
        if account.requiresProbeConfiguration {
            button.target = self
            button.action = #selector(open)
            button.bezelStyle = .rounded
            button.controlSize = .small
        } else {
            button.image = NSImage(
                systemSymbolName: refreshIconName,
                accessibilityDescription: "Refresh"
            )
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.controlSize = .small
            button.focusRingType = .none
            button.toolTip = "Refresh"
            button.isEnabled = !isRefreshing
        }

        bottom.addArrangedSubview(balanceStack)
        bottom.addArrangedSubview(NSView())
        bottom.addArrangedSubview(button)

        stack.addArrangedSubview(top)
        stack.addArrangedSubview(divider)
        stack.addArrangedSubview(bottom)

        if let warningText {
            stack.addArrangedSubview(label(warningText, size: 11, color: .systemOrange))
        }

        addSubview(stack)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private var warningText: String? {
        if account.requiresProbeConfiguration {
            return "Needs an owned app bundle ID to refresh balance."
        } else if let issue = account.lastIssue {
            return issue.message
        }
        return nil
    }

    private var refreshIconName: String {
        isRefreshing ? "hourglass" : "arrow.clockwise"
    }

    private var isRefreshing: Bool {
        if case .refreshing = refreshState {
            return true
        }
        return false
    }

    private var statusTitle: String {
        if isRefreshing {
            return "Syncing"
        }

        switch account.status {
        case .normal:
            return "Ready"
        case .needsVerification:
            return "2FA"
        case .sessionExpired:
            return "Expired"
        case .attention:
            return "Attention"
        }
    }

    private var statusTint: NSColor {
        if isRefreshing {
            return .controlAccentColor
        }

        switch account.status {
        case .normal:
            return .secondaryLabelColor
        case .needsVerification:
            return .systemOrange
        case .sessionExpired:
            return .systemRed
        case .attention:
            return .systemYellow
        }
    }

    private func makeAvatar() -> NSView {
        let view = NSTextField(labelWithString: String(account.displayName.prefix(1)).uppercased())
        view.font = .systemFont(ofSize: 12, weight: .medium)
        view.textColor = .white
        view.alignment = .center
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer?.backgroundColor = avatarColor.cgColor
        view.layer?.cornerRadius = 7
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 28),
            view.heightAnchor.constraint(equalToConstant: 28),
        ])
        return view
    }

    private var avatarColor: NSColor {
        let colors: [NSColor] = [
            .systemBlue,
            .systemPurple,
            .systemPink,
            .systemOrange,
            .systemTeal,
            .systemIndigo,
            .systemMint,
            .systemCyan,
        ]
        return colors[abs(account.email.hashValue) % colors.count]
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        monospaced: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    @objc
    private func open() {
        onOpen()
    }

    @objc
    private func refresh() {
        onRefresh()
    }
}
