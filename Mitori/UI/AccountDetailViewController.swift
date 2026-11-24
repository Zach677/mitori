//
//  AccountDetailViewController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/05/30.
//

import AppKit

@MainActor
final class AccountDetailViewController: NSViewController {
    private enum Metrics {
        static let maxContentWidth: CGFloat = 480
        static let horizontalInset: CGFloat = 28
        static let topInset: CGFloat = 8
        static let bottomInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 18
        static let heroBottomSpacing: CGFloat = 4
    }

    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let probeAppSearch: any ProbeAppSearching
    private let onRefreshRequested: @MainActor (String) -> Void

    private(set) var accountID: String?
    private var isDeleting = false
    private var deleteTask: Task<Void, Never>?
    private var currentIssueAction: AccountIssuePresentation.Action?
    private weak var copyFeedbackView: NSView?

    private let scrollView = NSScrollView()
    private let documentView = FlippedContentView()
    private let contentStack = NSStackView()

    private let heroStack = NSStackView()
    private let balanceLabel = NSTextField(labelWithString: "")
    private let updatedLabel = NSTextField(labelWithString: "")

    private let issueGroup = GroupedFormView()
    private let issueTextStack = NSStackView()
    private let issueIconView = NSImageView()
    private let issueTitleLabel = NSTextField(labelWithString: "")
    private let issueMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let issueMetaLabel = NSTextField(wrappingLabelWithString: "")
    private let issueActionButton = NSButton(title: "", target: nil, action: nil)

    private let accountGroup = GroupedFormView(title: "Account")
    private let appleIDButton = CopyableDetailButton(title: "", target: nil, action: nil)
    private let appleIDFallbackLabel = NSTextField(labelWithString: "")
    private let storeValueLabel = NSTextField(labelWithString: "")
    private let deviceIDButton = CopyableDetailButton(title: "", target: nil, action: nil)
    private let deviceIDFallbackLabel = NSTextField(labelWithString: "")

    private let refreshGroup = GroupedFormView(
        title: "Background Refresh",
        footnote: "Mitori reads the balance through this app with the saved session. It never sends your password in the background. Without an app, the balance refreshes only when you ask."
    )
    private let probeValueLabel = NSTextField(labelWithString: "")
    private let chooseProbeButton = NSButton(title: "Choose App…", target: nil, action: nil)

    private let actionErrorLabel = NSTextField(wrappingLabelWithString: "")
    private var signInAgainRow: NSView?
    private let signInAgainButton = NSButton(title: "Sign In Again…", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove Account…", target: nil, action: nil)

    private var account: StoredAccountMeta? {
        model.account(with: accountID)
    }

    init(
        model: MitoriModel,
        settings: RefreshSettingsStore,
        probeAppSearch: any ProbeAppSearching = ProbeAppSearchService(),
        onRefreshRequested: @escaping @MainActor (String) -> Void
    ) {
        self.model = model
        self.settings = settings
        self.probeAppSearch = probeAppSearch
        self.onRefreshRequested = onRefreshRequested
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        configureLayout()
        reload()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        deleteTask?.cancel()
        deleteTask = nil
    }

    func setAccountID(_ newAccountID: String?) {
        let changed = newAccountID != accountID
        accountID = newAccountID
        if changed {
            isDeleting = false
            actionErrorLabel.stringValue = ""
            actionErrorLabel.isHidden = true
        }
        reload()
    }

    func reload() {
        guard isViewLoaded else { return }

        guard let account,
              let accountIndex = model.accounts.firstIndex(where: { $0.id == account.id })
        else {
            contentStack.isHidden = true
            return
        }

        contentStack.isHidden = false
        let presentation = AccountPresentation(
            account: account,
            accountIndex: accountIndex,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        )
        let refreshState = model.refreshState(for: account.id)
        let issue = AccountIssuePresentation(
            account: account,
            nextAutoRefreshAt: model.nextAutoRefreshDate(for: account.id)
        )

        updateHero(account: account, refreshState: refreshState)
        updateIssue(issue)
        updateAccountInfo(account: account, presentation: presentation)
        updateBackgroundRefresh(account: account, issue: issue)
        updateBottomActions(issue: issue, refreshState: refreshState)
    }
}

private extension AccountDetailViewController {
    func configureLayout() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        documentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = Metrics.sectionSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        documentView.addSubview(contentStack)
        view.addSubview(scrollView)

        configureHero()
        configureIssueGroup()
        configureAccountGroup()
        configureBackgroundRefreshGroup()
        configureActionError()
        let footerRow = makeBottomActionsRow()

        addFullWidth(heroStack, to: contentStack)
        contentStack.setCustomSpacing(22, after: heroStack)
        addFullWidth(issueGroup, to: contentStack)
        addFullWidth(accountGroup, to: contentStack)
        addFullWidth(refreshGroup, to: contentStack)
        addFullWidth(actionErrorLabel, to: contentStack)
        addFullWidth(footerRow, to: contentStack)

        let widthCap = contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.maxContentWidth)
        let trailingFill = contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Metrics.horizontalInset)
        trailingFill.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: Metrics.horizontalInset),
            trailingFill,
            widthCap,
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -Metrics.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: Metrics.topInset),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -Metrics.bottomInset),
        ])
    }

    func configureHero() {
        heroStack.orientation = .vertical
        heroStack.alignment = .leading
        heroStack.spacing = Metrics.heroBottomSpacing

        balanceLabel.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
        balanceLabel.textColor = .labelColor
        balanceLabel.setAccessibilityIdentifier("account-detail.balance")

        updatedLabel.font = .systemFont(ofSize: 11)
        updatedLabel.textColor = .secondaryLabelColor
        updatedLabel.setAccessibilityIdentifier("account-detail.updated")

        heroStack.addArrangedSubview(balanceLabel)
        heroStack.addArrangedSubview(updatedLabel)
    }

    func configureIssueGroup() {
        issueIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        issueIconView.translatesAutoresizingMaskIntoConstraints = false
        issueIconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        issueIconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        issueTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        issueTitleLabel.textColor = .labelColor

        issueMessageLabel.font = .systemFont(ofSize: 12)
        issueMessageLabel.textColor = .secondaryLabelColor
        issueMessageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        issueMetaLabel.font = .systemFont(ofSize: 11)
        issueMetaLabel.textColor = .tertiaryLabelColor
        issueMetaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for label in [issueTitleLabel, issueMessageLabel, issueMetaLabel] {
            issueTextStack.addArrangedSubview(label)
        }
        issueTextStack.orientation = .vertical
        issueTextStack.alignment = .leading
        issueTextStack.spacing = 3

        issueActionButton.bezelStyle = .rounded
        issueActionButton.controlSize = .regular
        issueActionButton.target = self
        issueActionButton.action = #selector(handleIssueAction)
        issueActionButton.setContentHuggingPriority(.required, for: .horizontal)
        issueActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        issueActionButton.setAccessibilityIdentifier("account-detail.issue-action")

        let row = NSStackView(views: [issueIconView, issueTextStack, issueActionButton])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10

        issueGroup.addRow(row, minHeight: 44)
        // Only the text is one AX element, so the action button stays reachable as its sibling.
        issueTextStack.setAccessibilityElement(true)
        issueTextStack.setAccessibilityRole(.group)
        issueTextStack.setAccessibilityIdentifier("account-detail.issue")
        issueGroup.isHidden = true
    }

    func configureAccountGroup() {
        accountGroup.addRow(makeCopyableRow(
            title: "Apple ID",
            button: appleIDButton,
            fallbackLabel: appleIDFallbackLabel,
            monospaced: false
        ))
        accountGroup.addRow(makeKeyValueRow(title: "Store", valueLabel: storeValueLabel))
        accountGroup.addRow(makeCopyableRow(
            title: "Device ID",
            button: deviceIDButton,
            fallbackLabel: deviceIDFallbackLabel,
            monospaced: true
        ))

        signInAgainButton.bezelStyle = .rounded
        signInAgainButton.target = self
        signInAgainButton.action = #selector(openSignInAgainSheet)
        signInAgainButton.setContentHuggingPriority(.required, for: .horizontal)
        signInAgainButton.setAccessibilityIdentifier("account-detail.reauthenticate")

        let signInLabel = NSTextField(labelWithString: "Password or code changed")
        signInLabel.font = .systemFont(ofSize: 13)
        signInLabel.textColor = .labelColor
        signInLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [signInLabel, spacer, signInAgainButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        accountGroup.addRow(row)
        signInAgainRow = row
    }

    func configureBackgroundRefreshGroup() {
        let titleLabel = NSTextField(labelWithString: "App this Apple ID owns")
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        probeValueLabel.textColor = .secondaryLabelColor
        probeValueLabel.alignment = .right
        probeValueLabel.lineBreakMode = .byTruncatingMiddle
        probeValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        probeValueLabel.setAccessibilityIdentifier("account-detail.probe-value")

        chooseProbeButton.bezelStyle = .rounded
        chooseProbeButton.target = self
        chooseProbeButton.action = #selector(openChooseProbeSheet)
        chooseProbeButton.setContentHuggingPriority(.required, for: .horizontal)
        chooseProbeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        chooseProbeButton.setAccessibilityIdentifier("account-detail.choose-probe")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, probeValueLabel, chooseProbeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        refreshGroup.addRow(row)
    }

    func configureActionError() {
        actionErrorLabel.font = .systemFont(ofSize: 11.5)
        actionErrorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        actionErrorLabel.isHidden = true
    }

    func makeBottomActionsRow() -> NSView {
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(confirmRemoveAccount)
        removeButton.contentTintColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        removeButton.setAccessibilityIdentifier("account-detail.delete")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [spacer, removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    func makeKeyValueRow(title: String, valueLabel: NSTextField) -> NSView {
        let keyLabel = NSTextField(labelWithString: title)
        keyLabel.font = .systemFont(ofSize: 13)
        keyLabel.textColor = .labelColor

        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [keyLabel, spacer, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    func makeCopyableRow(
        title: String,
        button: CopyableDetailButton,
        fallbackLabel: NSTextField,
        monospaced: Bool
    ) -> NSView {
        let keyLabel = NSTextField(labelWithString: title)
        keyLabel.font = .systemFont(ofSize: 13)
        keyLabel.textColor = .labelColor

        button.isBordered = false
        button.focusRingType = .default
        button.alignment = .right
        button.font = monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 13)
        button.contentTintColor = .secondaryLabelColor
        button.cell?.lineBreakMode = .byTruncatingMiddle
        button.target = self
        button.action = #selector(copyValue(_:))
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp("Click to copy \(title)")
        button.setAccessibilityIdentifier("account-detail.copy.\(title)")

        fallbackLabel.font = monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 13)
        fallbackLabel.textColor = .secondaryLabelColor
        fallbackLabel.alignment = .right
        fallbackLabel.lineBreakMode = .byTruncatingMiddle

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [keyLabel, spacer, button, fallbackLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    func updateHero(account: StoredAccountMeta, refreshState: RefreshState) {
        balanceLabel.stringValue = account.balanceDisplayText ?? "Unavailable"
        if case .refreshing = refreshState {
            updatedLabel.stringValue = "Refreshing…"
            return
        }

        if let lastRefresh = account.lastRefreshAt {
            let formatted = lastRefresh.freshnessText()
            updatedLabel.stringValue = account.needsProbeBundleID
                ? "Updated \(formatted) · Refreshes when you ask"
                : "Updated \(formatted)"
        } else {
            updatedLabel.stringValue = account.needsProbeBundleID
                ? "Refreshes when you ask"
                : "Not refreshed yet"
        }
    }

    func updateIssue(_ issue: AccountIssuePresentation?) {
        currentIssueAction = issue?.action
        guard let issue else {
            issueGroup.isHidden = true
            issueTextStack.setAccessibilityValue("")
            return
        }

        issueGroup.isHidden = false
        issueIconView.image = NSImage(systemSymbolName: issue.symbolName, accessibilityDescription: issue.detailTitle)
        issueIconView.contentTintColor = issue.tintColor
        issueTitleLabel.stringValue = issue.detailTitle
        issueMessageLabel.stringValue = issue.message
        issueMetaLabel.stringValue = issue.metadata

        if let actionTitle = issue.actionTitle {
            issueActionButton.title = actionTitle
            issueActionButton.isHidden = false
        } else {
            issueActionButton.isHidden = true
        }
        issueTextStack.setAccessibilityLabel(issue.detailTitle)
        issueTextStack.setAccessibilityValue("\(issue.detailTitle). \(issue.message)")
    }

    func updateAccountInfo(account: StoredAccountMeta, presentation: AccountPresentation) {
        let exposesPII = !settings.isPersonalInformationHidden
        updateCopyable(
            button: appleIDButton,
            fallback: appleIDFallbackLabel,
            display: presentation.appleID,
            copyValue: exposesPII ? account.appleID : nil
        )
        storeValueLabel.stringValue = account.storeDisplayName
        updateCopyable(
            button: deviceIDButton,
            fallback: deviceIDFallbackLabel,
            display: presentation.deviceIdentifier,
            copyValue: exposesPII ? account.deviceIdentifier : nil
        )
    }

    func updateBackgroundRefresh(account: StoredAccountMeta, issue: AccountIssuePresentation?) {
        let appName = account.probeAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleID = account.probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bundle ID entered by hand is the only name Mitori knows for that app.
        let showsBundleID = appName.isEmpty && !bundleID.isEmpty
        if !appName.isEmpty {
            probeValueLabel.stringValue = appName
        } else if bundleID.isEmpty {
            probeValueLabel.stringValue = "None"
        } else {
            probeValueLabel.stringValue = settings.isPersonalInformationHidden ? "Hidden" : bundleID
        }
        probeValueLabel.font = showsBundleID && !settings.isPersonalInformationHidden
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 13)
        chooseProbeButton.title = bundleID.isEmpty ? "Choose App…" : "Change…"
        if account.visibleIssue?.kind == .probeConfigurationMissing {
            probeValueLabel.textColor = issue?.tintColor ?? .systemOrange
        } else {
            probeValueLabel.textColor = .secondaryLabelColor
        }
    }

    func updateBottomActions(issue: AccountIssuePresentation?, refreshState: RefreshState) {
        let isRefreshing: Bool = if case .refreshing = refreshState { true } else { false }
        let issueAlreadyOffersSignIn: Bool = switch issue?.action {
        case .signInAgain: true
        default: false
        }
        if let signInAgainRow {
            accountGroup.setRowHidden(signInAgainRow, issueAlreadyOffersSignIn)
        }
        signInAgainButton.isEnabled = !isDeleting && !isRefreshing
        chooseProbeButton.isEnabled = !isDeleting && !isRefreshing
        issueActionButton.isEnabled = !isDeleting && !isRefreshing
        removeButton.isEnabled = !isDeleting
    }

    func updateCopyable(
        button: CopyableDetailButton,
        fallback: NSTextField,
        display: String,
        copyValue: String?
    ) {
        if let copyValue {
            button.title = display
            button.copyValue = copyValue
            button.toolTip = "\(copyValue)\nClick to copy"
            button.isHidden = false
            fallback.isHidden = true
        } else {
            button.isHidden = true
            fallback.stringValue = display
            fallback.isHidden = false
        }
    }

    @objc
    func copyValue(_ sender: CopyableDetailButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sender.copyValue, forType: .string)
        showCopyToast()
    }

    func showCopyToast() {
        copyFeedbackView?.removeFromSuperview()

        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) ?? NSImage())
        check.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: "Copied")
        label.font = .systemFont(ofSize: 12, weight: .medium)

        let stack = NSStackView(views: [check, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let toast = NSVisualEffectView()
        toast.material = .popover
        toast.state = .active
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 14
        toast.alphaValue = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        toast.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toast.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: toast.trailingAnchor),
            stack.topAnchor.constraint(equalTo: toast.topAnchor),
            stack.bottomAnchor.constraint(equalTo: toast.bottomAnchor),
        ])

        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            toast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        copyFeedbackView = toast

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            toast.animator().alphaValue = 1
        }
        Task { @MainActor [weak self, weak toast] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let toast, copyFeedbackView === toast else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                toast.animator().alphaValue = 0
            }
            guard copyFeedbackView === toast else { return }
            toast.removeFromSuperview()
            copyFeedbackView = nil
        }
    }

    @objc
    func handleIssueAction() {
        guard let account, let action = currentIssueAction else { return }
        switch action {
        case let .signInAgain(requiresCode):
            presentSignInAgainSheet(requiresCode: requiresCode)
        case .chooseApp:
            openChooseProbeSheet()
        case .refresh:
            onRefreshRequested(account.id)
        }
    }

    @objc
    func openSignInAgainSheet() {
        let requiresCode = account?.visibleIssue?.kind == .requiresVerification
        presentSignInAgainSheet(requiresCode: requiresCode)
    }

    func presentSignInAgainSheet(requiresCode: Bool) {
        guard let account, let hostWindow = view.window else { return }
        let accountIndex = model.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
        let presentation = AccountPresentation(
            account: account,
            accountIndex: accountIndex,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        )

        var sheetWindow: NSWindow?
        let sheetVC = SignInAgainSheetController(
            model: model,
            accountID: account.id,
            accountLabel: presentation.name,
            requiresCodeInitially: requiresCode
        ) { [weak self] in
            if let sheetWindow {
                hostWindow.endSheet(sheetWindow)
            }
            self?.reload()
        }
        let window = NSWindow(contentViewController: sheetVC)
        window.styleMask = [.titled]
        sheetWindow = window
        hostWindow.beginSheet(window)
    }

    @objc
    func openChooseProbeSheet() {
        guard let account, let hostWindow = view.window else { return }
        let accountID = account.id
        var sheetWindow: NSWindow?
        let sheetVC = ChooseProbeAppSheetController(
            model: model,
            accountID: accountID,
            countryCode: account.countryCode,
            currentBundleID: account.probeBundleID,
            currentAppName: account.probeAppName,
            probeAppSearch: probeAppSearch
        ) { [weak self] probeChanged in
            if let sheetWindow {
                hostWindow.endSheet(sheetWindow)
            }
            guard let self else { return }
            reload()
            if probeChanged, let updated = model.account(with: accountID), !updated.needsProbeBundleID {
                onRefreshRequested(accountID)
            }
        }
        let window = NSWindow(contentViewController: sheetVC)
        window.styleMask = [.titled]
        sheetWindow = window
        hostWindow.beginSheet(window)
    }

    @objc
    func confirmRemoveAccount() {
        guard let account, !isDeleting else { return }
        let alert = NSAlert()
        alert.messageText = "Remove Account?"
        alert.informativeText = "Mitori will remove the account metadata and saved credentials from this Mac."
        alert.alertStyle = .warning
        let removeBtn = alert.addButton(withTitle: "Remove")
        removeBtn.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let performRemove: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            isDeleting = true
            actionErrorLabel.isHidden = true
            reload()
            deleteTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await model.deleteAccount(id: account.id)
                } catch {
                    isDeleting = false
                    actionErrorLabel.stringValue = MitoriError.map(error).localizedDescription
                    actionErrorLabel.isHidden = false
                    reload()
                }
            }
        }

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    Task { @MainActor in performRemove() }
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            performRemove()
        }
    }
}

@MainActor
private final class CopyableDetailButton: NSButton {
    var copyValue = ""
}

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}
