import AppKit

@MainActor
final class MenuPanelViewController: NSViewController {
    private enum Metrics {
        static let width: CGFloat = 360
        static let maxScrollHeight: CGFloat = 420
    }

    private let model: MitoriModel
    private let onAddAccount: @MainActor () -> Void
    private let onOpenAccount: @MainActor (String) -> Void
    private let onQuit: @MainActor () -> Void

    private let contentStack = NSStackView()
    private let accountsStack = NSStackView()
    private let accountScrollView = NSScrollView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private var accountScrollHeightConstraint: NSLayoutConstraint?

    init(
        model: MitoriModel,
        onAddAccount: @escaping @MainActor () -> Void,
        onOpenAccount: @escaping @MainActor (String) -> Void,
        onQuit: @escaping @MainActor () -> Void
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
        }
    }

    @objc
    func quit() {
        onQuit()
    }

    func refreshAccount(_ accountID: String) {
        Task {
            await model.refreshAccount(id: accountID, isManualRefresh: true)
        }
    }
}
