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

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await model.loadSecretSummary(for: accountID)
            reload()
        }
    }
}

private extension AccountDetailViewController {
    func configureLayout() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        contentStack.orientation = .vertical
        contentStack.spacing = 18
        contentStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: documentView.widthAnchor),
        ])

        scrollView.documentView = documentView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 480),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 520),
        ])
    }

    func reload(errorMessage: String? = nil) {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let account else {
            contentStack.addArrangedSubview(label("Account removed", size: 14, weight: .medium))
            return
        }

        if probeBundleIDField.stringValue.isEmpty {
            probeBundleIDField.stringValue = account.probeBundleID
        }

        contentStack.addArrangedSubview(makeHeader(account))
        contentStack.addArrangedSubview(makeBalanceSection(account))
        contentStack.addArrangedSubview(makeInfoSection(account))
        contentStack.addArrangedSubview(makeProbeSection(account))
        contentStack.addArrangedSubview(makeReauthSection())
        contentStack.addArrangedSubview(makeActionsSection())

        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.isHidden = errorMessage == nil
        if errorMessage != nil {
            contentStack.addArrangedSubview(errorLabel)
        }
    }

    func makeHeader(_ account: StoredAccountMeta) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12

        let avatar = NSTextField(labelWithString: String(account.displayName.prefix(1)).uppercased())
        avatar.font = .systemFont(ofSize: 18, weight: .medium)
        avatar.textColor = .white
        avatar.alignment = .center
        avatar.wantsLayer = true
        avatar.layer?.backgroundColor = avatarColor(for: account).cgColor
        avatar.layer?.cornerRadius = 10
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
        ])

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.spacing = 2
        identity.addArrangedSubview(label(account.displayName, size: 15, weight: .medium))
        identity.addArrangedSubview(label(account.email, size: 12, color: .secondaryLabelColor))

        stack.addArrangedSubview(avatar)
        stack.addArrangedSubview(identity)
        stack.addArrangedSubview(NSView())
        return stack
    }

    func makeBalanceSection(_ account: StoredAccountMeta) -> NSView {
        let stack = boxedStack()
        stack.addArrangedSubview(label("Balance", size: 11, weight: .medium, color: .secondaryLabelColor))
        stack.addArrangedSubview(label(
            account.balanceSnapshot?.displayText ?? "Unavailable",
            size: 28,
            weight: .semibold,
            monospaced: true
        ))
        if let lastRefresh = account.lastRefreshAt {
            stack.addArrangedSubview(label(
                "Updated \(lastRefresh.formatted(date: .abbreviated, time: .shortened))",
                size: 11,
                color: .tertiaryLabelColor
            ))
        }
        return stack
    }

    func makeInfoSection(_ account: StoredAccountMeta) -> NSView {
        let stack = section(title: "Account Info")
        stack.addArrangedSubview(detailRow("Apple ID", value: account.appleID))
        stack.addArrangedSubview(detailRow("Region", value: account.regionLabel.isEmpty ? "Unknown" : account.regionLabel))
        stack.addArrangedSubview(detailRow("Pod", value: account.pod ?? "Unavailable"))
        stack.addArrangedSubview(detailRow("DSID", value: model.secretSummary(for: accountID)))
        stack.addArrangedSubview(detailRow("Device ID", value: String(account.deviceIdentifier.prefix(12)) + "..."))
        return stack
    }

    func makeProbeSection(_ account: StoredAccountMeta) -> NSView {
        let stack = section(title: "Probe Bundle ID")
        probeBundleIDField.placeholderString = "Owned app bundle ID"
        stack.addArrangedSubview(probeBundleIDField)

        let searchRow = NSStackView()
        searchRow.orientation = .horizontal
        searchRow.spacing = 8
        probeSearchField.placeholderString = "Search app name"
        probeSearchField.target = self
        probeSearchField.action = #selector(searchProbeApps)

        let searchButton = NSButton(title: "Search", target: self, action: #selector(searchProbeApps))
        searchButton.bezelStyle = .rounded
        searchButton.controlSize = .small
        searchRow.addArrangedSubview(probeSearchField)
        searchRow.addArrangedSubview(searchButton)
        stack.addArrangedSubview(searchRow)

        if let searchError = probeLookup.errorMessage {
            stack.addArrangedSubview(label(searchError, size: 11, color: .systemOrange))
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
            stack.addArrangedSubview(probeResultsStack)
        }

        stack.addArrangedSubview(label("Pick any app this Apple ID already owns in \(account.countryCode ?? "US").", size: 11, color: .tertiaryLabelColor))

        saveProbeButton.target = self
        saveProbeButton.action = #selector(saveProbeBundleID)
        saveProbeButton.bezelStyle = .rounded
        saveProbeButton.controlSize = .small
        saveProbeButton.isEnabled = !isSavingProbe
        stack.addArrangedSubview(saveProbeButton)
        return stack
    }

    func makeReauthSection() -> NSView {
        let stack = section(title: "Re-authentication")
        verificationCodeField.placeholderString = "2FA Code (optional)"
        stack.addArrangedSubview(verificationCodeField)

        reauthButton.target = self
        reauthButton.action = #selector(reauthenticate)
        reauthButton.bezelStyle = .rounded
        reauthButton.controlSize = .small
        reauthButton.isEnabled = !isReauthing
        stack.addArrangedSubview(reauthButton)
        return stack
    }

    func makeActionsSection() -> NSView {
        let stack = section(title: "Actions")
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let refreshButton = NSButton(title: "Refresh Balance", target: self, action: #selector(refreshBalance))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small

        deleteButton.target = self
        deleteButton.action = #selector(deleteAccount)
        deleteButton.bezelStyle = .rounded
        deleteButton.controlSize = .small
        deleteButton.isEnabled = !isDeleting

        row.addArrangedSubview(refreshButton)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(deleteButton)
        stack.addArrangedSubview(row)
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
        stack.spacing = 8
        stack.addArrangedSubview(label(title, size: 11, weight: .medium, color: .secondaryLabelColor))
        return stack
    }

    func boxedStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        stack.layer?.cornerRadius = 8
        return stack
    }

    func detailRow(_ title: String, value: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12

        let titleLabel = label(title, size: 12, color: .secondaryLabelColor)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let valueLabel = label(value, size: 12)
        valueLabel.alignment = .right
        valueLabel.maximumNumberOfLines = 3
        valueLabel.lineBreakMode = .byTruncatingMiddle

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
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

    @objc
    func saveProbeBundleID() {
        guard !isSavingProbe else { return }
        isSavingProbe = true
        reload()

        Task {
            do {
                try await model.saveProbeBundleID(probeBundleIDField.stringValue, for: accountID)
                reload()
            } catch {
                reload(errorMessage: MitoriError.map(error).localizedDescription)
            }
            isSavingProbe = false
            reload()
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
