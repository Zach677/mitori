import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    private static let intervalChoices: [(title: String, interval: TimeInterval)] = [
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("3 hours", 3 * 60 * 60),
        ("6 hours", 6 * 60 * 60),
    ]

    private let settings: RefreshSettingsStore
    private let onOpenPrivacyPolicy: @MainActor () -> Void
    private let onOpenSourceLicenses: @MainActor () -> Void
    private let autoRefreshSwitch = NSSwitch()
    private let intervalPopUp = NSPopUpButton()

    init(
        settings: RefreshSettingsStore,
        onOpenPrivacyPolicy: @escaping @MainActor () -> Void,
        onOpenSourceLicenses: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.onOpenPrivacyPolicy = onOpenPrivacyPolicy
        self.onOpenSourceLicenses = onOpenSourceLicenses
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
}

private extension SettingsViewController {
    func configureLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 22
        root.translatesAutoresizingMaskIntoConstraints = false

        addFullWidth(makeHeader(), to: root)
        addFullWidth(makeRefreshSection(), to: root)
        addFullWidth(makeAboutSection(), to: root)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            view.widthAnchor.constraint(equalToConstant: 420),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
    }

    func makeHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Manage balance updates and app information.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    func makeRefreshSection() -> NSView {
        let stack = section(title: "Refresh")

        autoRefreshSwitch.target = self
        autoRefreshSwitch.action = #selector(toggleAutoRefresh)
        autoRefreshSwitch.controlSize = .small
        autoRefreshSwitch.focusRingType = .none
        addFullWidth(settingRow(title: "Refresh balances automatically", control: autoRefreshSwitch), to: stack)

        intervalPopUp.addItems(withTitles: Self.intervalChoices.map(\.title))
        intervalPopUp.target = self
        intervalPopUp.action = #selector(selectInterval)
        intervalPopUp.widthAnchor.constraint(equalToConstant: 142).isActive = true
        addFullWidth(settingRow(title: "Refresh every", control: intervalPopUp), to: stack)

        let help = NSTextField(wrappingLabelWithString: "Apple may flag frequent balance probes. Mitori limits the interval to 15 minutes and backs off after failures.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.maximumNumberOfLines = 3
        help.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addFullWidth(help, to: stack)
        return stack
    }

    func makeAboutSection() -> NSView {
        let stack = section(title: "About")
        stack.spacing = 6
        addFullWidth(documentRow(
            title: "Privacy Policy",
            symbolName: "arrow.up.right.square",
            accessibilityHelp: "Open the Mitori privacy policy in your browser.",
            action: #selector(openPrivacyPolicy)
        ), to: stack)
        addFullWidth(documentRow(
            title: "Open Source Licenses",
            symbolName: "doc.text",
            accessibilityHelp: "View third-party license terms bundled with Mitori.",
            action: #selector(openSourceLicenses)
        ), to: stack)
        return stack
    }

    func section(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        addFullWidth(sectionLabel(title), to: stack)
        return stack
    }

    func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    func settingRow(title: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)

        row.addArrangedSubview(label)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(control)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return row
    }

    func documentRow(
        title: String,
        symbolName: String,
        accessibilityHelp: String,
        action: Selector
    ) -> NSView {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.contentTintColor = .labelColor
        button.setAccessibilityHelp(accessibilityHelp)
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func reload() {
        autoRefreshSwitch.state = settings.isAutoRefreshEnabled ? .on : .off
        intervalPopUp.isEnabled = settings.isAutoRefreshEnabled

        let current = settings.autoRefreshInterval
        let index = Self.intervalChoices.firstIndex { $0.interval >= current }
            ?? Self.intervalChoices.indices.last!
        intervalPopUp.selectItem(at: index)
    }

    @objc
    func toggleAutoRefresh() {
        settings.isAutoRefreshEnabled = autoRefreshSwitch.state == .on
        reload()
    }

    @objc
    func selectInterval() {
        let index = intervalPopUp.indexOfSelectedItem
        guard Self.intervalChoices.indices.contains(index) else { return }
        settings.autoRefreshInterval = Self.intervalChoices[index].interval
    }

    @objc
    func openPrivacyPolicy() {
        onOpenPrivacyPolicy()
    }

    @objc
    func openSourceLicenses() {
        onOpenSourceLicenses()
    }
}
