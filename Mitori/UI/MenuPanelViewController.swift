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
        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(configureAccountScrollView())

        bannerLabel.font = .systemFont(ofSize: 11)
        bannerLabel.textColor = .secondaryLabelColor
        bannerLabel.lineBreakMode = .byWordWrapping
        bannerLabel.maximumNumberOfLines = 2
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(wrapped(bannerLabel, horizontal: 16, vertical: 6))

        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(makeFooter())
    }

    func makeHeader() -> NSView {
        let wrapper = NSView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Mitori")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

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

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(refreshButton)
        stack.addArrangedSubview(addButton)

        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10),
            refreshButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.widthAnchor.constraint(equalToConstant: 24),
        ])

        return wrapper
    }

    func configureAccountScrollView() -> NSView {
        accountsStack.orientation = .vertical
        accountsStack.alignment = .width
        accountsStack.spacing = 0
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
        summaryLabel.textColor = .secondaryLabelColor

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
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
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

        for (index, account) in model.accounts.enumerated() {
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
            if index < model.accounts.count - 1 {
                accountsStack.addArrangedSubview(makeRowSeparator())
            }
        }
        updateAccountDocumentFrame()
    }

    func makeEmptyState() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 16, bottom: 28, right: 16)

        let title = NSTextField(labelWithString: "No accounts yet")
        title.font = .systemFont(ofSize: 13, weight: .medium)

        let subtitle = NSTextField(wrappingLabelWithString: "Add an Apple ID to start tracking balances.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let button = NSButton(title: "Add Account", target: self, action: #selector(addAccount))
        button.bezelStyle = .rounded
        button.controlSize = .small

        [title, subtitle, button].forEach(stack.addArrangedSubview(_:))
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.width - 32).isActive = true
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
        let minimumHeight: CGFloat = model.accounts.isEmpty ? 120 : 0
        let visibleHeight = min(max(fittingHeight, minimumHeight), Metrics.maxScrollHeight)
        accountsStack.frame = NSRect(x: 0, y: 0, width: documentWidth, height: fittingHeight)
        accountScrollHeightConstraint?.constant = visibleHeight
    }

    func updatePanelSize() {
        view.layoutSubtreeIfNeeded()
        let height = min(max(contentStack.fittingSize.height, 160), 540)
        preferredContentSize = NSSize(width: Metrics.width, height: height)
    }

    func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    func makeRowSeparator() -> NSView {
        let wrapper = NSView()
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            wrapper.heightAnchor.constraint(equalToConstant: 1),
        ])
        return wrapper
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
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 1
        identity.addArrangedSubview(label(account.displayName, size: 12, weight: .medium))
        identity.addArrangedSubview(label(account.email, size: 11, color: .secondaryLabelColor))

        let trailing = NSStackView()
        trailing.orientation = .vertical
        trailing.alignment = .trailing
        trailing.spacing = 1
        trailing.addArrangedSubview(balanceLabel)
        if let hint {
            trailing.addArrangedSubview(label(hint, size: 11, color: hintColor))
        }

        let button = makeActionButton()

        stack.addArrangedSubview(identity)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(trailing)
        stack.addArrangedSubview(button)

        addSubview(stack)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private var balanceLabel: NSTextField {
        let text: String
        if isRefreshing {
            text = "…"
        } else {
            text = account.balanceSnapshot?.displayText ?? "—"
        }
        return label(text, size: 15, weight: .medium, monospaced: true)
    }

    private var hint: String? {
        if isRefreshing { return nil }
        if account.requiresProbeConfiguration { return "Set up probe app" }
        switch account.status {
        case .normal:
            return nil
        case .needsVerification:
            return "2FA required"
        case .sessionExpired:
            return "Session expired"
        case .attention:
            return "Needs attention"
        }
    }

    private var hintColor: NSColor {
        switch account.status {
        case .sessionExpired:
            return NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        default:
            return NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange
        }
    }

    private var isRefreshing: Bool {
        if case .refreshing = refreshState {
            return true
        }
        return false
    }

    private func makeActionButton() -> NSButton {
        let button = NSButton()
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.controlSize = .small
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true

        if account.requiresProbeConfiguration {
            button.title = "Set Up"
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.isBordered = true
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.target = self
            button.action = #selector(open)
        } else {
            button.image = NSImage(systemSymbolName: refreshIconName, accessibilityDescription: "Refresh")
            button.toolTip = "Refresh"
            button.target = self
            button.action = #selector(refresh)
            button.isEnabled = !isRefreshing
        }
        return button
    }

    private var refreshIconName: String {
        isRefreshing ? "hourglass" : "arrow.clockwise"
    }

    private func makeAvatar() -> NSView {
        let view = NSTextField(labelWithString: String(account.displayName.prefix(1)).uppercased())
        view.font = .systemFont(ofSize: 12, weight: .semibold)
        view.textColor = .white
        view.alignment = .center
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer?.backgroundColor = avatarColor.cgColor
        view.layer?.cornerRadius = 12
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 24),
            view.heightAnchor.constraint(equalToConstant: 24),
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
