import AppKit

@MainActor
final class AccountDetailViewController: NSViewController {
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

    private var probeLookup = ProbeAppLookupModel()
    private var isSavingProbe = false
    private var isReauthing = false
    private var isDeleting = false
    private weak var copyFeedbackView: NSView?

    private let contentStack = NSStackView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let probeBundleIDField = NSTextField()
    private let probeSearchField = NSTextField()
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
        onClose: @escaping @MainActor () -> Void,
        onProbeSaved: @escaping @MainActor (Bool) -> Void
    ) {
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

    func reload(errorMessage: String? = nil) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let account else {
            addFullWidth(label("Account removed", size: 14, weight: .medium), to: contentStack)
            return
        }

        if probeBundleIDField.stringValue.isEmpty {
            probeBundleIDField.stringValue = account.probeBundleID
        }

        addFullWidth(makeBalanceSection(account), to: contentStack)
        addFullWidth(makeInfoSection(account), to: contentStack)
        addFullWidth(makeReauthSection(), to: contentStack)
        addFullWidth(makeProbeSection(account), to: contentStack)

        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.isHidden = errorMessage == nil
        if errorMessage != nil {
            addFullWidth(errorLabel, to: contentStack)
        }
        contentStack.invalidateIntrinsicContentSize()
        view.layoutSubtreeIfNeeded()
        if let window = view.window {
            let contentHeight = contentStack.fittingSize.height + view.safeAreaInsets.top
            window.setContentSize(NSSize(
                width: window.contentView?.bounds.width ?? Metrics.width,
                height: contentHeight
            ))
        }
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

        configureErrorLabel()

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: Metrics.width),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumHeight),
        ])
    }

    func makeBalanceSection(_ account: StoredAccountMeta) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Metrics.balanceSpacing
        addFullWidth(label("Balance", size: 11, weight: .medium, color: .secondaryLabelColor), to: stack)
        addFullWidth(label(
            account.balanceDisplayText ?? "Unavailable",
            size: 18,
            weight: .medium,
            monospaced: true
        ), to: stack)
        if let lastRefresh = account.lastRefreshAt {
            addFullWidth(label(
                "Updated \(lastRefresh.formatted(date: .abbreviated, time: .shortened))",
                size: 11,
                color: .tertiaryLabelColor
            ), to: stack)
        }
        return stack
    }

    func makeInfoSection(_ account: StoredAccountMeta) -> NSView {
        let accountIndex = model.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
        let presentation = AccountPresentation(
            account: account,
            accountIndex: accountIndex,
            hidesPersonalInformation: settings.isPersonalInformationHidden
        )
        let stack = section(title: "Account Info")
        let exposesPersonalInformation = !settings.isPersonalInformationHidden
        addFullWidth(detailRow(
            "Apple ID",
            value: presentation.appleID,
            copyValue: exposesPersonalInformation ? account.appleID : nil
        ), to: stack)
        addFullWidth(detailRow("Region", value: account.regionLabel.isEmpty ? "Unknown" : account.regionLabel), to: stack)
        addFullWidth(detailRow("Pod", value: account.pod ?? "Unavailable"), to: stack)
        addFullWidth(detailRow("Credentials", value: "Stored in Keychain"), to: stack)
        addFullWidth(detailRow(
            "Device ID",
            value: presentation.deviceIdentifier,
            copyValue: exposesPersonalInformation ? account.deviceIdentifier : nil
        ), to: stack)
        return stack
    }

    func makeProbeSection(_ account: StoredAccountMeta) -> NSView {
        let stack = section(title: "Probe App")
        probeBundleIDField.placeholderString = "Owned app bundle ID"
        probeBundleIDField.font = .systemFont(ofSize: 13)
        addFullWidth(probeBundleIDField, to: stack)

        let searchRow = NSStackView()
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 8
        probeSearchField.placeholderString = "Search app name"
        probeSearchField.font = .systemFont(ofSize: 13)
        probeSearchField.target = self
        probeSearchField.action = #selector(searchProbeApps)
        probeSearchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let searchButton = NSButton(title: "Search", target: self, action: #selector(searchProbeApps))
        searchButton.bezelStyle = .rounded
        searchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        searchButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        searchRow.addArrangedSubview(probeSearchField)
        searchRow.addArrangedSubview(searchButton)
        addFullWidth(searchRow, to: stack)

        if let searchError = probeLookup.errorMessage {
            addFullWidth(label(searchError, size: 11, color: NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange), to: stack)
        }

        let resultsStack = NSStackView()
        resultsStack.orientation = .vertical
        resultsStack.spacing = 4
        for result in probeLookup.results {
            resultsStack.addArrangedSubview(resultButton(result))
        }
        if !probeLookup.results.isEmpty {
            addFullWidth(resultsStack, to: stack)
        }

        addFullWidth(label("Pick any app this Apple ID already owns in \(account.countryCode ?? "US").", size: 11, color: .secondaryLabelColor), to: stack)

        saveProbeButton.target = self
        saveProbeButton.action = #selector(saveProbeBundleID)
        saveProbeButton.bezelStyle = .rounded
        saveProbeButton.isEnabled = !isSavingProbe && !isReauthing && !isDeleting
        saveProbeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        deleteButton.target = self
        deleteButton.action = #selector(deleteAccount)
        deleteButton.bezelStyle = .rounded
        deleteButton.contentTintColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        deleteButton.isEnabled = !isDeleting && !isSavingProbe && !isReauthing
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
        addFullWidth(actionRow, to: stack)
        return stack
    }

    func makeReauthSection() -> NSView {
        let stack = section(title: "Re-authentication")
        verificationCodeField.placeholderString = "2FA Code (optional)"
        verificationCodeField.font = .systemFont(ofSize: 13)
        addFullWidth(verificationCodeField, to: stack)

        reauthButton.target = self
        reauthButton.action = #selector(reauthenticate)
        reauthButton.bezelStyle = .rounded
        reauthButton.isEnabled = !isReauthing && !isSavingProbe && !isDeleting
        addFullWidth(buttonRow(trailing: reauthButton), to: stack)
        return stack
    }

    func resultButton(_ result: ProbeAppCandidate) -> NSButton {
        let button = ProbeResultButton(title: "\(result.name)  \(result.bundleID)", target: self, action: #selector(selectProbeResult(_:)))
        button.bezelStyle = .inline
        button.alignment = .left
        button.result = result
        return button
    }

    func section(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        addFullWidth(label(title, size: 11, weight: .medium, color: .secondaryLabelColor), to: stack)
        return stack
    }

    func detailRow(_ title: String, value: String, copyValue: String? = nil) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12

        let titleLabel = label(title, size: 12, color: .secondaryLabelColor)
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let valueLabel: NSTextField
        if let copyValue {
            let button = CopyableValueButton(title: value, target: self, action: #selector(copyDetailValue(_:)))
            button.copyValue = copyValue
            button.toolTip = "\(copyValue)\nClick to copy"
            button.isBordered = false
            button.focusRingType = .none
            button.font = .systemFont(ofSize: 12)
            button.alignment = .left
            button.contentTintColor = .labelColor
            button.setAccessibilityLabel(title)
            button.setAccessibilityHelp("Click to copy \(title)")
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.cell?.lineBreakMode = .byTruncatingMiddle

            row.addArrangedSubview(titleLabel)
            row.addArrangedSubview(button)
            return row
        }

        valueLabel = label(value, size: 12)
        valueLabel.alignment = .left
        valueLabel.maximumNumberOfLines = 3
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
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
        )!)
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

        let feedback = NSGlassEffectView()
        feedback.contentView = content
        feedback.cornerRadius = 14
        feedback.style = .clear
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
        errorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 4
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        let horizontalInsets = stack.edgeInsets.left + stack.edgeInsets.right
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -horizontalInsets).isActive = true
    }

    func label(
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
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 4
        return field
    }

    @objc
    func saveProbeBundleID() {
        guard !isSavingProbe, !isReauthing, !isDeleting else { return }
        let oldProbe = (account?.probeBundleID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newProbe = probeBundleIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        isSavingProbe = true
        reload()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await model.saveProbeBundleID(probeBundleIDField.stringValue, for: accountID)
                onProbeSaved(oldProbe != newProbe)
            } catch {
                isSavingProbe = false
                reload(errorMessage: MitoriError.map(error).localizedDescription)
            }
        }
    }

    @objc
    func reauthenticate() {
        guard !isReauthing, !isSavingProbe, !isDeleting else { return }
        isReauthing = true
        reload()

        Task {
            var errorMessage: String?
            do {
                try await model.reauthenticateAccount(id: accountID, code: verificationCodeField.stringValue)
                verificationCodeField.stringValue = ""
            } catch {
                errorMessage = MitoriError.map(error).localizedDescription
            }
            isReauthing = false
            reload(errorMessage: errorMessage)
        }
    }

    @objc
    func deleteAccount() {
        guard !isDeleting, confirmDeletion() else { return }
        isDeleting = true
        reload()

        Task {
            do {
                try await model.deleteAccount(id: accountID)
                onClose()
            } catch {
                isDeleting = false
                reload(errorMessage: MitoriError.map(error).localizedDescription)
            }
        }
    }

    @objc
    func searchProbeApps() {
        guard let account, !isDeleting else { return }
        probeLookup.query = probeSearchField.stringValue
        Task {
            await probeLookup.search(countryCode: account.countryCode)
            reload()
        }
    }

    @objc
    func selectProbeResult(_ sender: ProbeResultButton) {
        guard let result = sender.result else { return }
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
