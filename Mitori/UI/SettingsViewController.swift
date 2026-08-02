import AppKit
import ServiceManagement

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
    private let onPersonalInformationVisibilityChanged: @MainActor () -> Void
    private let onOpenPrivacyPolicy: @MainActor () -> Void
    private let onOpenSourceLicenses: @MainActor () -> Void
    private let openAtLoginSwitch = NSSwitch()
    private let hidePersonalInformationSwitch = NSSwitch()
    private let autoRefreshSwitch = NSSwitch()
    private let intervalPopUp = NSPopUpButton()
    private weak var intervalSettingView: NSView?

    init(
        settings: RefreshSettingsStore,
        onPersonalInformationVisibilityChanged: @escaping @MainActor () -> Void,
        onOpenPrivacyPolicy: @escaping @MainActor () -> Void,
        onOpenSourceLicenses: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.onPersonalInformationVisibilityChanged = onPersonalInformationVisibilityChanged
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
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false

        addFullWidth(makeGeneralSection(), to: root)
        addFullWidth(makeRefreshSection(), to: root)
        addFullWidth(makeAboutSection(), to: root)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            view.widthAnchor.constraint(equalToConstant: 420),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])
    }

    func makeGeneralSection() -> NSView {
        let stack = section(title: "General")

        openAtLoginSwitch.target = self
        openAtLoginSwitch.action = #selector(toggleOpenAtLogin)
        openAtLoginSwitch.controlSize = .small
        addFullWidth(settingBlock(title: "Open at login", control: openAtLoginSwitch), to: stack)

        hidePersonalInformationSwitch.target = self
        hidePersonalInformationSwitch.action = #selector(togglePersonalInformationVisibility)
        hidePersonalInformationSwitch.controlSize = .small
        addFullWidth(settingBlock(
            title: "Hide personal information",
            help: "Hides account names, email addresses, Apple IDs, and device IDs in Mitori.",
            control: hidePersonalInformationSwitch
        ), to: stack)
        return stack
    }

    func makeRefreshSection() -> NSView {
        let stack = section(title: "Refresh")

        autoRefreshSwitch.target = self
        autoRefreshSwitch.action = #selector(toggleAutoRefresh)
        autoRefreshSwitch.controlSize = .small
        addFullWidth(settingBlock(
            title: "Refresh balances automatically",
            control: autoRefreshSwitch
        ), to: stack)

        intervalPopUp.addItems(withTitles: Self.intervalChoices.map(\.title))
        intervalPopUp.target = self
        intervalPopUp.action = #selector(selectInterval)
        intervalPopUp.widthAnchor.constraint(equalToConstant: 142).isActive = true
        let intervalSetting = settingBlock(
            title: "Refresh every",
            help: "Minimum 15 minutes. Mitori automatically backs off after failed refreshes.",
            control: intervalPopUp
        )
        intervalSettingView = intervalSetting
        addFullWidth(intervalSetting, to: stack)
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
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    func settingBlock(title: String, help: String? = nil, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 4
        addFullWidth(settingRow(title: title, control: control), to: stack)

        if let help {
            let label = NSTextField(wrappingLabelWithString: help)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addFullWidth(label, to: stack)
        }
        return stack
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
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
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
        button.focusRingType = .default
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
        openAtLoginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        hidePersonalInformationSwitch.state = settings.isPersonalInformationHidden ? .on : .off
        autoRefreshSwitch.state = settings.isAutoRefreshEnabled ? .on : .off
        let isAutoRefreshEnabled = settings.isAutoRefreshEnabled
        intervalPopUp.isEnabled = isAutoRefreshEnabled
        intervalSettingView?.alphaValue = isAutoRefreshEnabled ? 1 : 0.65

        let current = settings.autoRefreshInterval
        let index = Self.intervalChoices.firstIndex { $0.interval >= current }
            ?? Self.intervalChoices.indices.last!
        intervalPopUp.selectItem(at: index)
    }

    @objc
    func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if openAtLoginSwitch.state == .on {
                try service.register()
                if service.status == .requiresApproval {
                    showLoginItemAlert(
                        message: "Allow Mitori in System Settings to open it automatically when you log in.",
                        offersSystemSettings: true
                    )
                }
            } else {
                try service.unregister()
            }
        } catch {
            showLoginItemAlert(
                message: error.localizedDescription,
                offersSystemSettings: service.status == .requiresApproval
            )
        }
        reload()
    }

    @objc
    func togglePersonalInformationVisibility() {
        settings.isPersonalInformationHidden = hidePersonalInformationSwitch.state == .on
        onPersonalInformationVisibilityChanged()
        reload()
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

    func showLoginItemAlert(message: String, offersSystemSettings: Bool) {
        let alert = NSAlert()
        alert.messageText = "Unable to change login setting"
        alert.informativeText = message
        alert.alertStyle = .warning
        if offersSystemSettings {
            alert.addButton(withTitle: "Open System Settings")
        }
        alert.addButton(withTitle: "OK")

        guard let window = view.window else {
            if offersSystemSettings, alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
            return
        }
        alert.beginSheetModal(for: window) { response in
            if offersSystemSettings, response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
