//
//  SettingsViewController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/06/12.
//

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
    private let onDockIconPolicyChanged: @MainActor () -> Void
    private let onPersonalInformationVisibilityChanged: @MainActor () -> Void
    private let onRefreshSettingsChanged: @MainActor () -> Void
    private let onOpenPrivacyPolicy: @MainActor () -> Void
    private let onOpenSourceLicenses: @MainActor () -> Void

    private let openAtLoginSwitch = NSSwitch()
    private let hideDockIconSwitch = NSSwitch()
    private let hidePersonalInformationSwitch = NSSwitch()
    private let autoRefreshSwitch = NSSwitch()
    private let intervalPopUp = NSPopUpButton()
    private weak var intervalRowView: NSView?

    init(
        settings: RefreshSettingsStore,
        onDockIconPolicyChanged: @escaping @MainActor () -> Void = {},
        onPersonalInformationVisibilityChanged: @escaping @MainActor () -> Void,
        onRefreshSettingsChanged: @escaping @MainActor () -> Void = {},
        onOpenPrivacyPolicy: @escaping @MainActor () -> Void,
        onOpenSourceLicenses: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.onDockIconPolicyChanged = onDockIconPolicyChanged
        self.onPersonalInformationVisibilityChanged = onPersonalInformationVisibilityChanged
        self.onRefreshSettingsChanged = onRefreshSettingsChanged
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

    func reload() {
        guard isViewLoaded else { return }
        openAtLoginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        hideDockIconSwitch.state = settings.hidesDockIconWhenClosed ? .on : .off
        hidePersonalInformationSwitch.state = settings.isPersonalInformationHidden ? .on : .off

        let isAutoRefreshEnabled = settings.isAutoRefreshEnabled
        autoRefreshSwitch.state = isAutoRefreshEnabled ? .on : .off
        intervalPopUp.isEnabled = isAutoRefreshEnabled
        intervalRowView?.alphaValue = isAutoRefreshEnabled ? 1 : 0.55

        let current = settings.autoRefreshInterval
        let index = Self.intervalChoices.firstIndex { $0.interval >= current }
            ?? Self.intervalChoices.indices.last!
        intervalPopUp.selectItem(at: index)
    }
}

private extension SettingsViewController {
    func configureLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false

        addFullWidth(makeGeneralGroup(), to: root)
        addFullWidth(makeRefreshGroup(), to: root)
        addFullWidth(makeAboutGroup(), to: root)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            view.widthAnchor.constraint(equalToConstant: 500),
        ])
    }

    func makeGeneralGroup() -> GroupedFormView {
        let group = GroupedFormView(
            title: "General",
            footnote: "With the Dock icon hidden, Mitori stays in the menu bar only after you close its windows. Hidden personal information shows accounts as “Account 1”, “Account 2”."
        )

        openAtLoginSwitch.target = self
        openAtLoginSwitch.action = #selector(toggleOpenAtLogin)
        openAtLoginSwitch.controlSize = .small
        openAtLoginSwitch.setAccessibilityIdentifier("settings.open-at-login")
        group.addRow(settingRow(title: "Open at login", control: openAtLoginSwitch))

        hideDockIconSwitch.target = self
        hideDockIconSwitch.action = #selector(toggleHideDockIcon)
        hideDockIconSwitch.controlSize = .small
        hideDockIconSwitch.setAccessibilityIdentifier("settings.hide-dock-icon")
        group.addRow(settingRow(title: "Hide Dock icon when window is closed", control: hideDockIconSwitch))

        hidePersonalInformationSwitch.target = self
        hidePersonalInformationSwitch.action = #selector(togglePersonalInformationVisibility)
        hidePersonalInformationSwitch.controlSize = .small
        hidePersonalInformationSwitch.setAccessibilityIdentifier("settings.hide-personal-information")
        group.addRow(settingRow(title: "Hide personal information", control: hidePersonalInformationSwitch))
        return group
    }

    func makeRefreshGroup() -> GroupedFormView {
        let group = GroupedFormView(
            title: "Refresh",
            footnote: "Only accounts with a background refresh app refresh automatically. Mitori never sends a password in the background."
        )

        autoRefreshSwitch.target = self
        autoRefreshSwitch.action = #selector(toggleAutoRefresh)
        autoRefreshSwitch.controlSize = .small
        autoRefreshSwitch.setAccessibilityIdentifier("settings.auto-refresh")
        group.addRow(settingRow(title: "Refresh balances automatically", control: autoRefreshSwitch))

        intervalPopUp.addItems(withTitles: Self.intervalChoices.map(\.title))
        intervalPopUp.target = self
        intervalPopUp.action = #selector(selectInterval)
        intervalPopUp.setAccessibilityIdentifier("settings.interval")
        intervalPopUp.widthAnchor.constraint(equalToConstant: 136).isActive = true

        let intervalRow = settingRow(title: "Refresh every", control: intervalPopUp)
        intervalRowView = intervalRow
        group.addRow(intervalRow)
        return group
    }

    func makeAboutGroup() -> GroupedFormView {
        let group = GroupedFormView(title: "About")
        group.addRow(documentRow(
            title: "Privacy Policy",
            accessibilityHelp: "Open the Mitori privacy policy in your browser.",
            identifier: "settings.privacy-policy",
            action: #selector(openPrivacyPolicy)
        ))
        group.addRow(documentRow(
            title: "Open Source Licenses",
            accessibilityHelp: "View third-party license terms bundled with Mitori.",
            identifier: "settings.licenses",
            action: #selector(openSourceLicenses)
        ))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let versionLabel = NSTextField(labelWithString: version)
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true
        versionLabel.setAccessibilityIdentifier("settings.version")
        group.addRow(settingRow(title: "Version", control: versionLabel))
        return group
    }

    func settingRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(title)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    func documentRow(
        title: String,
        accessibilityHelp: String,
        identifier: String,
        action: Selector
    ) -> NSView {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13)
        button.contentTintColor = .labelColor
        button.focusRingType = .default
        button.setAccessibilityHelp(accessibilityHelp)
        button.setAccessibilityIdentifier(identifier)

        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        // The button stretches so the whole row is the click target.
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [button, chevron])
        row.distribution = .fill
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
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
    func toggleHideDockIcon() {
        settings.hidesDockIconWhenClosed = hideDockIconSwitch.state == .on
        onDockIconPolicyChanged()
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
        onRefreshSettingsChanged()
        reload()
    }

    @objc
    func selectInterval() {
        let index = intervalPopUp.indexOfSelectedItem
        guard Self.intervalChoices.indices.contains(index) else { return }
        settings.autoRefreshInterval = Self.intervalChoices[index].interval
        onRefreshSettingsChanged()
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
