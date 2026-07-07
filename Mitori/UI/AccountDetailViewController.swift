import AppKit

@MainActor
final class AccountDetailViewController: NSViewController {
    private let model: MitoriModel
    private let accountID: String
    private let onClose: () -> Void

    private var probeLookup = ProbeAppLookupModel()
    private var isSavingProbe = false
    private var isReauthing = false
    private var isDeleting = false

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let probeBundleIDField = NSTextField()
    private let probeSearchField = NSTextField()
    private let probeResultsStack = NSStackView()
    private let verificationCodeField = NSTextField()
    private let saveProbeButton = NSButton(title: "Save", target: nil, action: nil)
    private let reauthButton = NSButton(title: "Re-authenticate", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)

    private var account: StoredAccountMeta? {
        model.account(with: accountID)
    }

    init(model: MitoriModel, accountID: String, onClose: @escaping () -> Void) {
        self.model = model
        self.accountID = accountID
        self.onClose = onClose
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

    override func viewDidLayout() {
        super.viewDidLayout()
    }
}

private extension AccountDetailViewController {
    func configureLayout() {
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 24
        contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 16, right: 24)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(contentStack)

        configureErrorLabel()

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 500),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 520),
        ])
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
    }

    func makeHeader(_ account: StoredAccountMeta) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2
        identity.addArrangedSubview(label(account.displayName, size: 14, weight: .semibold))
        identity.addArrangedSubview(label(account.email, size: 11, color: .secondaryLabelColor))
        identity.addArrangedSubview(label(statusTitle(for: account), size: 11, color: statusTint(for: account)))

        stack.addArrangedSubview(identity)
        stack.addArrangedSubview(NSView())
        return stack
    }

    func makeBalanceSection(_ account: StoredAccountMeta) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        addFullWidth(label("Balance", size: 11, weight: .medium, color: .secondaryLabelColor), to: stack)
        addFullWidth(label(
            account.balanceSnapshot?.displayText ?? "Unavailable",
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
        let stack = section(title: "Account Info")
        addFullWidth(detailRow("Apple ID", value: account.appleID), to: stack)
        addFullWidth(detailRow("Region", value: account.regionLabel.isEmpty ? "Unknown" : account.regionLabel), to: stack)
        addFullWidth(detailRow("Pod", value: account.pod ?? "Unavailable"), to: stack)
        addFullWidth(detailRow("Credentials", value: "Stored in Keychain"), to: stack)
        addFullWidth(detailRow("Device ID", value: String(account.deviceIdentifier.prefix(12)) + "…"), to: stack)
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

        probeResultsStack.orientation = .vertical
        probeResultsStack.spacing = 4
        probeResultsStack.arrangedSubviews.forEach { view in
            probeResultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for result in probeLookup.results {
            probeResultsStack.addArrangedSubview(resultButton(result))
        }
        if !probeLookup.results.isEmpty {
            addFullWidth(probeResultsStack, to: stack)
        }

        addFullWidth(label("Pick any app this Apple ID already owns in \(account.countryCode ?? "US").", size: 11, color: .secondaryLabelColor), to: stack)

        saveProbeButton.target = self
        saveProbeButton.action = #selector(saveProbeBundleID)
        saveProbeButton.bezelStyle = .rounded
        saveProbeButton.isEnabled = !isSavingProbe
        saveProbeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        deleteButton.target = self
        deleteButton.action = #selector(deleteAccount)
        deleteButton.bezelStyle = .rounded
        deleteButton.contentTintColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        deleteButton.isEnabled = !isDeleting
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
        reauthButton.isEnabled = !isReauthing
        addFullWidth(buttonRow(trailing: reauthButton), to: stack)
        return stack
    }

    func makeActionsSection() -> NSView {
        let stack = section(title: "Actions")
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let refreshButton = NSButton(title: "Refresh Balance", target: self, action: #selector(refreshBalance))
        refreshButton.bezelStyle = .rounded

        deleteButton.target = self
        deleteButton.action = #selector(deleteAccount)
        deleteButton.bezelStyle = .rounded
        deleteButton.contentTintColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor)
        deleteButton.isEnabled = !isDeleting

        row.addArrangedSubview(refreshButton)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(deleteButton)
        addFullWidth(row, to: stack)
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

    func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    func detailRow(_ title: String, value: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12

        let titleLabel = label(title, size: 12, color: .secondaryLabelColor)
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let valueLabel = label(value, size: 12)
        valueLabel.alignment = .left
        valueLabel.maximumNumberOfLines = 3
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
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

    func updateDocumentFrame() {
        let width = max(view.bounds.width, 500)
        let fittingHeight = contentStack.fittingSize.height
        let viewHeight = scrollView.contentView.bounds.height
        let y = max(0, viewHeight - fittingHeight)
        contentStack.frame = NSRect(x: 0, y: y, width: width, height: fittingHeight)
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

    func avatarColor(for account: StoredAccountMeta) -> NSColor {
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

    func statusTitle(for account: StoredAccountMeta) -> String {
        switch account.status {
        case .normal:
            return "Ready"
        case .needsVerification:
            return "Needs verification"
        case .sessionExpired:
            return "Session expired"
        case .attention:
            return "Needs attention"
        }
    }

    func statusTint(for account: StoredAccountMeta) -> NSColor {
        switch account.status {
        case .normal:
            return .secondaryLabelColor
        case .needsVerification, .attention:
            return NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange
        case .sessionExpired:
            return NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        }
    }

    @objc
    func saveProbeBundleID() {
        guard !isSavingProbe else { return }
        isSavingProbe = true
        reload()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await model.saveProbeBundleID(probeBundleIDField.stringValue, for: accountID)
                onClose()
            } catch {
                reload(errorMessage: MitoriError.map(error).localizedDescription)
                isSavingProbe = false
                reload()
            }
        }
    }

    @objc
    func refreshBalance() {
        Task {
            await model.refreshAccount(id: accountID, isManualRefresh: true)
            reload(errorMessage: model.account(with: accountID)?.lastIssue?.message)
        }
    }

    @objc
    func reauthenticate() {
        guard !isReauthing else { return }
        isReauthing = true
        reload()

        Task {
            do {
                try await model.reauthenticateAccount(id: accountID, code: verificationCodeField.stringValue)
                verificationCodeField.stringValue = ""
                reload()
            } catch {
                reload(errorMessage: MitoriError.map(error).localizedDescription)
            }
            isReauthing = false
            reload()
        }
    }

    @objc
    func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        reload()

        Task {
            await model.deleteAccount(id: accountID)
            onClose()
        }
    }

    @objc
    func searchProbeApps() {
        guard let account else { return }
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
}

@MainActor
private final class ProbeResultButton: NSButton {
    var result: ProbeAppCandidate?
}
