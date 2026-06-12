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
    private let autoRefreshCheckbox = NSButton(checkboxWithTitle: "Refresh balances automatically", target: nil, action: nil)
    private let intervalPopUp = NSPopUpButton()

    init(settings: RefreshSettingsStore) {
        self.settings = settings
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
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Auto Refresh")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor

        autoRefreshCheckbox.target = self
        autoRefreshCheckbox.action = #selector(toggleAutoRefresh)

        let intervalRow = NSStackView()
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 8

        let intervalLabel = NSTextField(labelWithString: "Refresh every")
        intervalLabel.font = .systemFont(ofSize: 13)

        intervalPopUp.addItems(withTitles: Self.intervalChoices.map(\.title))
        intervalPopUp.target = self
        intervalPopUp.action = #selector(selectInterval)

        intervalRow.addArrangedSubview(intervalLabel)
        intervalRow.addArrangedSubview(intervalPopUp)

        let help = NSTextField(wrappingLabelWithString: "Frequent balance probes can get an Apple ID flagged, so 15 minutes is the shortest interval. Failed accounts back off automatically.")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor

        root.addArrangedSubview(title)
        root.addArrangedSubview(autoRefreshCheckbox)
        root.addArrangedSubview(intervalRow)
        root.addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            view.widthAnchor.constraint(equalToConstant: 380),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
    }

    func reload() {
        autoRefreshCheckbox.state = settings.isAutoRefreshEnabled ? .on : .off
        intervalPopUp.isEnabled = settings.isAutoRefreshEnabled

        let current = settings.autoRefreshInterval
        let index = Self.intervalChoices.firstIndex { $0.interval >= current }
            ?? Self.intervalChoices.indices.last!
        intervalPopUp.selectItem(at: index)
    }

    @objc
    func toggleAutoRefresh() {
        settings.isAutoRefreshEnabled = autoRefreshCheckbox.state == .on
        reload()
    }

    @objc
    func selectInterval() {
        let index = intervalPopUp.indexOfSelectedItem
        guard Self.intervalChoices.indices.contains(index) else { return }
        settings.autoRefreshInterval = Self.intervalChoices[index].interval
    }
}
