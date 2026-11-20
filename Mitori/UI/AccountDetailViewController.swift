//
//  AccountDetailViewController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/05/30.
//

import AppKit

@MainActor
final class AccountDetailViewController: NSViewController, NSTextFieldDelegate {
    private enum Metrics {
        static let width: CGFloat = 500
        static let minimumHeight: CGFloat = 300
        static let horizontalInset: CGFloat = 24
        static let topInset: CGFloat = 8
        static let bottomInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
        static let balanceSpacing: CGFloat = 4
    }

    private let model: MitoriModel
    private let settings: RefreshSettingsStore
    private let accountID: String
    private let onClose: @MainActor () -> Void
    private let onProbeSaved: @MainActor (Bool) -> Void

    private var probeLookup: ProbeAppLookupModel
    private let reauthFlow = AddAccountFlowModel(mode: .reauthenticate)
    private var hasLoadedProbeField = false
    private var isSavingProbe = false
    private var isDeleting = false
    private var errorMessage: String?
    private var displayedSearchResults: [ProbeAppCandidate] = []
    private var selectedProbeCandidate: ProbeAppCandidate?
    private weak var copyFeedbackView: NSView?

    private let contentStack = NSStackView()
    private let removedLabel = NSTextField(labelWithString: "Account removed")
    private let balanceSection = NSStackView()
    private let balanceLabel = NSTextField(labelWithString: "")
    private let updatedLabel = NSTextField(labelWithString: "")
    private let infoSection = NSStackView()
    private let appleIDButton = CopyableValueButton(title: "", target: nil, action: nil)
    private let appleIDValueLabel = NSTextField(labelWithString: "")
    private let regionValueLabel = NSTextField(labelWithString: "")
    private let podValueLabel = NSTextField(labelWithString: "")
    private let deviceIDButton = CopyableValueButton(title: "", target: nil, action: nil)
    private let deviceIDValueLabel = NSTextField(labelWithString: "")
    private let reauthSection = NSStackView()
    private let reauthGuidanceLabel = NSTextField(labelWithString: "")
    private let reauthRecoveryButton = NSButton(title: "Open account.apple.com", target: nil, action: nil)
    private let probeSection = NSStackView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let probeBundleIDField = NSTextField()
    private let probeSearchField = NSTextField()
    private let probeSearchButton = NSButton(title: "Search", target: nil, action: nil)
    private let probeSearchErrorLabel = NSTextField(labelWithString: "")
    private let probeResultsStack = NSStackView()
    private let verificationCodeField = NSTextField()
    private let saveProbeButton = NSButton(title: "Save", target: nil, action: nil)
    private let reauthButton = NSButton(title: "Re-authenticate", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)

    private var account: StoredAccountMeta? {
        model.account(with: accountID)
    }

    init(
        model: MitoriModel,
        settings: RefreshSettingsStore,
        accountID: String,
        probeAppSearch: any ProbeAppSearching = ProbeAppSearchService(),
        onClose: @escaping @MainActor () -> Void,
        onProbeSaved: @escaping @MainActor (Bool) -> Void
    ) {
        probeLookup = ProbeAppLookupModel(searchService: probeAppSearch)
        self.model = model
        self.settings = settings
        self.accountID = accountID
        self.onClose = onClose
        self.onProbeSaved = onProbeSaved
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        configureLayout()
        reload()
    }

    func reload() {
        guard isViewLoaded else { return }

        guard let account else {
            removedLabel.isHidden = false
            balanceSection.isHidden = true
            infoSection.isHidden = true
            reauthSection.isHidden = true
            probeSection.isHidden = true
            errorLabel.isHidden = true
            updateWindowHeight()
            return
        }

        removedLabel.isHidden = true
        balanceSection.isHidden = false
        infoSection.isHidden = false
        reauthSection.isHidden = false
        probeSection.isHidden = false

        if !hasLoadedProbeField {
            probeBundleIDField.stringValue = account.probeBundleID
            hasLoadedProbeField = true
        }

        updateBalanceSection(account)
        updateInfoSection(account)
        updateReauthSection()
        updateProbeSection()

        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.isHidden = errorMessage == nil
        updateWindowHeight()
    }
}

private extension AccountDetailViewController {
    func configureLayout() {
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = Metrics.sectionSpacing
        contentStack.edgeInsets = NSEdgeInsets(
            top: Metrics.topInset,
            left: Metrics.horizontalInset,
            bottom: Metrics.bottomInset,
            right: Metrics.horizontalInset
        )
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(contentStack)

        removedLabel.font = .systemFont(ofSize: 14, weight: .medium)
        removedLabel.isHidden = true
        addFullWidth(removedLabel, to: contentStack)

        configureBalanceSection()
        configureInfoSection()
        configureReauthSection()
        configureProbeSection()
        configureErrorLabel()

        addFullWidth(balanceSection, to: contentStack)
        addFullWidth(infoSection, to: contentStack)
        addFullWidth(reauthSection, to: contentStack)
        addFullWidth(probeSection, to: contentStack)
        addFullWidth(errorLabel, to: contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: Metrics.width),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumHeight),
        ])
    }

    func configureBalanceSection() {
        balanceSection.orientation = .vertical
        balanceSection.alignment = .width
        balanceSection.spacing = Metrics.balanceSpacing
        addFullWidth(label("Balance", size: 11, weight: .medium, color: .secondaryLabelColor), to: balanceSection)

        configureLabel(balanceLabel, size: 18, weight: .medium, monospaced: true)
        balanceLabel.setAccessibilityIdentifier("account-detail.balance")
        addFullWidth(balanceLabel, to: balanceSection)

        configureLabel(updatedLabel, size: 11, color: .tertiaryLabelColor)
        addFullWidth(updatedLabel, to: balanceSection)
    }

    func configureInfoSection() {
        configureSection(infoSection, title: "Account Info")
        addFullWidth(
            copyableDetailRow("Apple ID", button: appleIDButton, fallbackLabel: appleIDValueLabel),
            to: infoSection
        )
        addFullWidth(detailRow("Region", valueLabel: regionValueLabel), to: infoSection)
        addFullWidth(detailRow("Pod", valueLabel: podValueLabel), to: infoSection)
        let credentialsLabel = label("Stored in Keychain", size: 12)
        addFullWidth(detailRow("Credentials", valueLabel: credentialsLabel), to: infoSection)
        addFullWidth(
            copyableDetailRow("Device ID", button: deviceIDButton, fallbackLabel: deviceIDValueLabel),
            to: infoSection
        )
    }

    func configureReauthSection() {
        configureSection(reauthSection, title: "Re-authentication")
        configureLabel(reauthGuidanceLabel, size: 11, color: .secondaryLabelColor)
        reauthGuidanceLabel.isHidden = true
        addFullWidth(reauthGuidanceLabel, to: reauthSection)

        verificationCodeField.placeholderString = "2FA Code (optional)"
        verificationCodeField.font = .systemFont(ofSize: 13)
        verificationCodeField.delegate = self
        verificationCodeField.setAccessibilityIdentifier("account-detail.code")
        addFullWidth(verificationCodeField, to: reauthSection)

        reauthRecoveryButton.bezelStyle = .inline
        reauthRecoveryButton.alignment = .left
        reauthRecoveryButton.target = self
        reauthRecoveryButton.action = #selector(openRecoveryLink)
        reauthRecoveryButton.setAccessibilityIdentifier("account-detail.recovery")
        reauthRecoveryButton.isHidden = true
        reauthSection.addArrangedSubview(reauthRecoveryButton)

        reauthButton.target = self
        reauthButton.action = #selector(reauthenticate)
        reauthButton.bezelStyle = .rounded
        reauthButton.setAccessibilityIdentifier("account-detail.reauthenticate")
        addFullWidth(buttonRow(trailing: reauthButton), to: reauthSection)
    }

    func configureProbeSection() {
        configureSection(probeSection, title: "Background Refresh")
        probeBundleIDField.placeholderString = "Owned app bundle ID (optional)"
        probeBundleIDField.font = .systemFont(ofSize: 13)
        probeBundleIDField.setAccessibilityIdentifier("account-detail.probe-bundle-id")
        addFullWidth(probeBundleIDField, to: probeSection)

        let searchRow = NSStackView()
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 8
        probeSearchField.placeholderString = "Search app name"
        probeSearchField.font = .systemFont(ofSize: 13)
        probeSearchField.target = self
        probeSearchField.action = #selector(searchProbeApps)
        probeSearchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        probeSearchField.setAccessibilityIdentifier("account-detail.probe-search")

        probeSearchButton.target = self
        probeSearchButton.action = #selector(searchProbeApps)
        probeSearchButton.bezelStyle = .rounded
        probeSearchButton.setAccessibilityIdentifier("account-detail.probe-search-button")
        probeSearchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        probeSearchButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        searchRow.addArrangedSubview(probeSearchField)
        searchRow.addArrangedSubview(probeSearchButton)
        addFullWidth(searchRow, to: probeSection)

        configureLabel(
            probeSearchErrorLabel,
            size: 11,
            color: NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange
        )
        probeSearchErrorLabel.isHidden = true
        addFullWidth(probeSearchErrorLabel, to: probeSection)

        probeResultsStack.orientation = .vertical
        probeResultsStack.alignment = .leading
        probeResultsStack.spacing = 4
        probeResultsStack.isHidden = true
        addFullWidth(probeResultsStack, to: probeSection)

        addFullWidth(label(
            "Optional. An app this Apple ID already owns lets Mitori refresh without signing in again.",
            size: 11,
            color: .secondaryLabelColor
        ), to: probeSection)

        saveProbeButton.target = self
        saveProbeButton.action = #selector(saveProbeBundleID)
        saveProbeButton.bezelStyle = .rounded
        saveProbeButton.setAccessibilityIdentifier("account-detail.save-probe")
        saveProbeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        deleteButton.target = self
        deleteButton.action = #selector(deleteAccount)
        deleteButton.bezelStyle = .rounded
        deleteButton.setAccessibilityIdentifier("account-detail.delete")
        deleteButton.contentTintColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        deleteButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionRow.addArrangedSubview(spacer)
        actionRow.addArrangedSubview(deleteButton)
        actionRow.addArrangedSubview(saveProbeButton)
        addFullWidth(actionRow, to: probeSection)
    }

    func updateBalanceSection(_ account: StoredAccountMeta) {
        balanceLabel.stringValue = account.balanceDisplayText ?? "Unavailable"
        if let lastRefresh = account.lastRefreshAt {
            updatedLabel.stringValue = "Updated \(lastRefresh.formatted(date: .abbreviated, time: .shortened))"
            updatedLabel.isHidden = false
        } else {
            updatedLabel.stringValue = ""
            updatedLabel.isHidden = true
        }
    }

    func updateInfoSection(_ account: StoredAccountMeta) {
        let accountIndex = model.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
        let presentation = AccountPresentation(
            account: account,
            accountIndex: accountIndex,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        )
        let exposesPersonalInformation = !settings.isPersonalInformationHidden

        updateCopyableField(
            button: appleIDButton,
            fallbackLabel: appleIDValueLabel,
            displayValue: presentation.appleID,
            copyValue: exposesPersonalInformation ? account.appleID : nil
        )
        regionValueLabel.stringValue = account.regionLabel.isEmpty ? "Unknown" : account.regionLabel
        podValueLabel.stringValue = account.pod ?? "Unavailable"
        updateCopyableField(
            button: deviceIDButton,
            fallbackLabel: deviceIDValueLabel,
            displayValue: presentation.deviceIdentifier,
            copyValue: exposesPersonalInformation ? account.deviceIdentifier : nil
        )
    }

    func updateReauthSection() {
        reauthFlow.verificationCode = verificationCodeField.stringValue
        reauthGuidanceLabel.stringValue = reauthFlow.showsVerificationCode ? reauthFlow.twoFactorMessage : ""
        reauthGuidanceLabel.isHidden = !reauthFlow.showsVerificationCode
        reauthRecoveryButton.title = reauthFlow.recoveryLink?.title ?? "Open account.apple.com"
        reauthRecoveryButton.isHidden = reauthFlow.recoveryLink == nil
        reauthButton.isEnabled = reauthFlow.canSubmit && !isSavingProbe && !isDeleting
    }

    func updateProbeSection() {
        probeSearchButton.title = probeLookup.isSearching ? "Searching..." : "Search"
        probeSearchButton.isEnabled = !probeLookup.isSearching && !isDeleting

        if let searchError = probeLookup.errorMessage {
            probeSearchErrorLabel.stringValue = searchError
            probeSearchErrorLabel.isHidden = false
        } else {
            probeSearchErrorLabel.stringValue = ""
            probeSearchErrorLabel.isHidden = true
        }

        if probeLookup.results != displayedSearchResults {
            displayedSearchResults = probeLookup.results
            probeResultsStack.arrangedSubviews.forEach { view in
                probeResultsStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for result in displayedSearchResults {
                probeResultsStack.addArrangedSubview(resultButton(result))
            }
            probeResultsStack.isHidden = displayedSearchResults.isEmpty
        }

        saveProbeButton.isEnabled = !isSavingProbe && !reauthFlow.isSubmitting && !isDeleting
        deleteButton.isEnabled = !isDeleting && !isSavingProbe && !reauthFlow.isSubmitting
    }

    func updateWindowHeight() {
        contentStack.invalidateIntrinsicContentSize()
        view.layoutSubtreeIfNeeded()
        if let window = view.window {
            let contentHeight = contentStack.fittingSize.height + view.safeAreaInsets.top
            let currentHeight = window.contentView?.bounds.height ?? 0
            if abs(contentHeight - currentHeight) > 0.5 {
                window.setContentSize(NSSize(
                    width: window.contentView?.bounds.width ?? Metrics.width,
                    height: contentHeight
                ))
            }
        }
    }

    func resultButton(_ result: ProbeAppCandidate) -> NSButton {
        let button = ProbeResultButton(title: "\(result.name)  \(result.bundleID)", target: self, action: #selector(selectProbeResult(_:)))
        button.bezelStyle = .inline
        button.alignment = .left
        button.result = result
        button.setAccessibilityIdentifier("account-detail.probe-result.\(result.bundleID)")
        return button
    }

    func configureSection(_ stack: NSStackView, title: String) {
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        addFullWidth(label(title, size: 11, weight: .medium, color: .secondaryLabelColor), to: stack)
    }

    func copyableDetailRow(
        _ title: String,
        button: CopyableValueButton,
        fallbackLabel: NSTextField
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12

        let titleLabel = detailTitleLabel(title)
        button.target = self
        button.action = #selector(copyDetailValue(_:))
        button.isBordered = false
        button.focusRingType = .none
        button.font = .systemFont(ofSize: 12)
        button.alignment = .left
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp("Click to copy \(title)")
        button.setAccessibilityIdentifier("account-detail.copy.\(title)")
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.cell?.lineBreakMode = .byTruncatingMiddle

        configureDetailValueLabel(fallbackLabel)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(button)
        row.addArrangedSubview(fallbackLabel)
        return row
    }

    func detailRow(_ title: String, valueLabel: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12

        configureDetailValueLabel(valueLabel)
        row.addArrangedSubview(detailTitleLabel(title))
        row.addArrangedSubview(valueLabel)
        return row
    }

    func detailTitleLabel(_ title: String) -> NSTextField {
        let titleLabel = label(title, size: 12, color: .secondaryLabelColor)
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return titleLabel
    }

    func configureDetailValueLabel(_ valueLabel: NSTextField) {
        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .left
        valueLabel.maximumNumberOfLines = 3
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func updateCopyableField(
        button: CopyableValueButton,
        fallbackLabel: NSTextField,
        displayValue: String,
        copyValue: String?
    ) {
        if let copyValue {
            button.title = displayValue
            button.copyValue = copyValue
            button.toolTip = "\(copyValue)\nClick to copy"
            button.isHidden = false
            fallbackLabel.isHidden = true
        } else {
            button.isHidden = true
            fallbackLabel.stringValue = displayValue
            fallbackLabel.isHidden = false
        }
    }

    @objc
    func copyDetailValue(_ sender: CopyableValueButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sender.copyValue, forType: .string)
        showCopyFeedback()
    }

    func showCopyFeedback() {
        copyFeedbackView?.removeFromSuperview()

        let checkmark = NSImageView(image: NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        ) ?? NSImage())
        checkmark.contentTintColor = .labelColor
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.widthAnchor.constraint(equalToConstant: 12).isActive = true
        checkmark.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let feedbackLabel = label("Copied", size: 12, weight: .medium)
        let content = NSStackView(views: [checkmark, feedbackLabel])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 5
        content.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let feedback: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.contentView = content
            glass.cornerRadius = 14
            glass.style = .clear
            feedback = glass
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .popover
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 14
            content.translatesAutoresizingMaskIntoConstraints = false
            visualEffect.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
                content.topAnchor.constraint(equalTo: visualEffect.topAnchor),
                content.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            ])
            feedback = visualEffect
        }
        feedback.alphaValue = 0
        feedback.translatesAutoresizingMaskIntoConstraints = false
        feedback.setAccessibilityLabel("Copied to clipboard")
        view.addSubview(feedback)
        NSLayoutConstraint.activate([
            feedback.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            feedback.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        copyFeedbackView = feedback

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            feedback.animator().alphaValue = 1
        }

        Task { @MainActor [weak self, weak feedback] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let feedback, copyFeedbackView === feedback else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                feedback.animator().alphaValue = 0
            }
            guard copyFeedbackView === feedback else { return }
            feedback.removeFromSuperview()
            copyFeedbackView = nil
        }
    }

    func buttonRow(trailing button: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(button)
        return row
    }

    func configureErrorLabel() {
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.setAccessibilityIdentifier("account-detail.error")
        errorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 4
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.isHidden = true
    }

    func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        monospaced: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        configureLabel(field, size: size, weight: weight, color: color, monospaced: monospaced)
        return field
    }

    func configureLabel(
        _ field: NSTextField,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        monospaced: Bool = false
    ) {
        field.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 4
    }

    @objc
    func saveProbeBundleID() {
        guard !isSavingProbe, !reauthFlow.isSubmitting, !isDeleting else { return }
        let oldProbe = (account?.probeBundleID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newProbe = probeBundleIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedAdamID = selectedProbeCandidate?.bundleID == newProbe ? selectedProbeCandidate?.id : nil
        isSavingProbe = true
        errorMessage = nil
        reload()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await model.saveProbeBundleID(newProbe, adamID: selectedAdamID, for: accountID)
                onProbeSaved(oldProbe != newProbe)
            } catch {
                isSavingProbe = false
                errorMessage = MitoriError.map(error).localizedDescription
                reload()
            }
        }
    }

    @objc
    func reauthenticate() {
        reauthFlow.verificationCode = verificationCodeField.stringValue
        guard reauthFlow.canSubmit, !isSavingProbe, !isDeleting else { return }
        reauthFlow.beginSubmission()
        errorMessage = nil
        reload()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await model.reauthenticateAccount(id: accountID, code: reauthFlow.verificationCode)
                reauthFlow.resetAfterSuccess()
                verificationCodeField.stringValue = ""
            } catch is CancellationError {
                reauthFlow.finishSubmission()
            } catch {
                reauthFlow.finishSubmission()
                reauthFlow.handleFailure(error)
                errorMessage = reauthFlow.errorMessage
            }
            reload()
        }
    }

    @objc
    func openRecoveryLink() {
        guard let url = reauthFlow.recoveryLink?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    func deleteAccount() {
        guard !isDeleting, confirmDeletion() else { return }
        isDeleting = true
        errorMessage = nil
        reload()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await model.deleteAccount(id: accountID)
                onClose()
            } catch {
                isDeleting = false
                errorMessage = MitoriError.map(error).localizedDescription
                reload()
            }
        }
    }

    @objc
    func searchProbeApps() {
        guard let account, !isDeleting else { return }
        probeLookup.query = probeSearchField.stringValue
        Task { [weak self] in
            guard let self else { return }
            let searchTask = Task { @MainActor in
                await self.probeLookup.search(countryCode: account.countryCode)
            }
            reload()
            await searchTask.value
            reload()
        }
    }

    @objc
    func selectProbeResult(_ sender: ProbeResultButton) {
        guard let result = sender.result else { return }
        selectedProbeCandidate = result
        probeBundleIDField.stringValue = probeLookup.select(result)
        reload()
    }

    func confirmDeletion() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete this account?"
        alert.informativeText = "Mitori will remove the account metadata and stored credentials from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
private final class ProbeResultButton: NSButton {
    var result: ProbeAppCandidate?
}

@MainActor
private final class CopyableValueButton: NSButton {
    var copyValue = ""
}

extension AccountDetailViewController {
    func controlTextDidChange(_: Notification) {
        updateReauthSection()
    }
}
