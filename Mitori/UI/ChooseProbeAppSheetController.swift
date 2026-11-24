//
//  ChooseProbeAppSheetController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/24.
//

import AppKit

@MainActor
final class ChooseProbeAppSheetController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let model: MitoriModel
    private let accountID: String
    private let countryCode: String?
    private let probeLookup: ProbeAppLookupModel
    private let onDismiss: @MainActor (Bool) -> Void

    private let initialBundleID: String
    private let initialAppName: String?
    private var selectedCandidate: ProbeAppCandidate?
    private var displayedResults: [ProbeAppCandidate] = []
    private var isSaving = false
    private var saveErrorMessage: String?
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    private let searchField = NSSearchField()
    private let searchErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let resultsTable = NSTableView()
    private let resultsScrollView = NSScrollView()
    private let manualDisclosure = NSButton()
    private let manualGrid = NSGridView()
    private let bundleIDField = NSTextField()
    private let spinner = NSProgressIndicator()
    private let saveErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let clearButton = NSButton(title: "Remove App", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    init(
        model: MitoriModel,
        accountID: String,
        countryCode: String?,
        currentBundleID: String,
        currentAppName: String?,
        probeAppSearch: any ProbeAppSearching,
        onDismiss: @escaping @MainActor (Bool) -> Void
    ) {
        self.model = model
        self.accountID = accountID
        self.countryCode = countryCode
        initialBundleID = currentBundleID
        initialAppName = currentAppName
        probeLookup = ProbeAppLookupModel(searchService: probeAppSearch)
        self.onDismiss = onDismiss
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
        bundleIDField.stringValue = initialBundleID
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        searchTask?.cancel()
        saveTask?.cancel()
    }
}

private extension ChooseProbeAppSheetController {
    func configureLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Choose Background Refresh App")
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "Pick an app this Apple ID already owns so Mitori can check your balance using your saved session without sending your password.")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        addFullWidth(header, to: root)

        searchField.placeholderString = "Search the App Store"
        searchField.sendsWholeSearchString = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchApps)
        searchField.setAccessibilityIdentifier("account-detail.probe-search")
        addFullWidth(searchField, to: root)

        searchErrorLabel.font = .systemFont(ofSize: 11)
        searchErrorLabel.textColor = NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange
        searchErrorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addFullWidth(searchErrorLabel, to: root)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        resultsTable.addTableColumn(column)
        resultsTable.headerView = nil
        resultsTable.style = .inset
        resultsTable.rowHeight = 24
        resultsTable.allowsEmptySelection = true
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.setAccessibilityLabel("Apps")
        resultsScrollView.documentView = resultsTable
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.autohidesScrollers = true
        resultsScrollView.borderType = .bezelBorder
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.heightAnchor.constraint(equalToConstant: 132).isActive = true
        addFullWidth(resultsScrollView, to: root)

        manualDisclosure.bezelStyle = .disclosure
        manualDisclosure.setButtonType(.pushOnPushOff)
        manualDisclosure.title = ""
        manualDisclosure.target = self
        manualDisclosure.action = #selector(toggleManualEntry)
        manualDisclosure.setAccessibilityLabel("Enter a bundle ID")
        manualDisclosure.setAccessibilityIdentifier("account-detail.probe-manual")
        let manualLabel = NSTextField(labelWithString: "Enter a bundle ID")
        manualLabel.font = .systemFont(ofSize: 11)
        manualLabel.textColor = .secondaryLabelColor
        let manualRow = NSStackView(views: [manualDisclosure, manualLabel])
        manualRow.orientation = .horizontal
        manualRow.alignment = .centerY
        manualRow.spacing = 4
        root.addArrangedSubview(manualRow)

        let bundleLabel = NSTextField(labelWithString: "Bundle ID:")
        bundleLabel.alignment = .right

        bundleIDField.placeholderString = "com.example.app"
        bundleIDField.setAccessibilityIdentifier("account-detail.probe-bundle-id")

        manualGrid.addRow(with: [bundleLabel, bundleIDField])
        manualGrid.columnSpacing = 8
        manualGrid.column(at: 0).xPlacement = .trailing
        manualGrid.column(at: 1).xPlacement = .fill
        manualGrid.rowAlignment = .firstBaseline
        manualGrid.isHidden = true
        addFullWidth(manualGrid, to: root)

        saveErrorLabel.font = .systemFont(ofSize: 11.5)
        saveErrorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        saveErrorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addFullWidth(saveErrorLabel, to: root)

        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearAndSave)
        clearButton.setAccessibilityIdentifier("account-detail.clear-probe")

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.setAccessibilityIdentifier("account-detail.probe-cancel")

        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.setAccessibilityIdentifier("account-detail.save-probe")

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel("Searching")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [clearButton, spinner, spacer, cancelButton, saveButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        addFullWidth(actions, to: root)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            view.widthAnchor.constraint(equalToConstant: 460),
        ])
    }

    func reload() {
        if probeLookup.isSearching || isSaving {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }

        let searchError = probeLookup.errorMessage ?? ""
        searchErrorLabel.stringValue = searchError
        searchErrorLabel.isHidden = searchError.isEmpty

        if probeLookup.results != displayedResults {
            displayedResults = probeLookup.results
            resultsTable.reloadData()
            if let selectedCandidate, let row = displayedResults.firstIndex(of: selectedCandidate) {
                resultsTable.selectRowIndexes([row], byExtendingSelection: false)
            }
        }
        resultsScrollView.isHidden = displayedResults.isEmpty

        let saveError = saveErrorMessage ?? ""
        saveErrorLabel.stringValue = saveError
        saveErrorLabel.isHidden = saveError.isEmpty

        clearButton.isHidden = initialBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        clearButton.isEnabled = !isSaving
        saveButton.isEnabled = !isSaving
    }

    @objc
    func searchApps() {
        guard !isSaving else { return }
        probeLookup.query = searchField.stringValue
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            let runTask = Task { @MainActor in
                await self.probeLookup.search(countryCode: self.countryCode)
            }
            reload()
            await runTask.value
            reload()
        }
    }

    @objc
    func toggleManualEntry() {
        manualGrid.isHidden = manualDisclosure.state == .off
        if !manualGrid.isHidden {
            view.window?.makeFirstResponder(bundleIDField)
        }
    }

    @objc
    func clearAndSave() {
        bundleIDField.stringValue = ""
        selectedCandidate = nil
        save()
    }

    @objc
    func save() {
        guard !isSaving else { return }
        let oldProbe = initialBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProbe = bundleIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedCandidate = selectedCandidate?.bundleID == newProbe ? selectedCandidate : nil
        let adamID = matchedCandidate?.id
        let appName: String? = if let matchedCandidate {
            matchedCandidate.name
        } else if newProbe == oldProbe {
            initialAppName
        } else {
            nil
        }

        isSaving = true
        saveErrorMessage = nil
        reload()

        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await model.saveProbeBundleID(newProbe, adamID: adamID, appName: appName, for: accountID)
                onDismiss(oldProbe != newProbe)
            } catch {
                isSaving = false
                saveErrorMessage = MitoriError.map(error).localizedDescription
                reload()
            }
        }
    }

    @objc
    func cancel() {
        searchTask?.cancel()
        saveTask?.cancel()
        onDismiss(false)
    }
}

extension ChooseProbeAppSheetController {
    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Return in the search field searches; it must not trigger the default Save button.
        guard control === searchField, commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        searchApps()
        return true
    }

    func numberOfRows(in _: NSTableView) -> Int {
        displayedResults.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let candidate = displayedResults[row]
        let identifier = NSUserInterfaceItemIdentifier("app-cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = candidate.name
        cell.textField?.setAccessibilityIdentifier("account-detail.probe-result.\(candidate.bundleID)")
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        let row = resultsTable.selectedRow
        guard displayedResults.indices.contains(row) else { return }
        selectedCandidate = displayedResults[row]
        bundleIDField.stringValue = displayedResults[row].bundleID
    }
}
