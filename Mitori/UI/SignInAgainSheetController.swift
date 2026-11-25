//
//  SignInAgainSheetController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/25.
//

import AppKit

@MainActor
final class SignInAgainSheetController: NSViewController, NSTextFieldDelegate {
    private let model: MitoriModel
    private let accountID: String
    private let accountLabel: String
    private let onDismiss: @MainActor () -> Void
    private let flow = AddAccountFlowModel(mode: .reauthenticate)

    private let passwordField = NSSecureTextField()
    private let codeField = NSTextField()
    private var codeRow: NSGridRow?
    private let guidanceLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let recoveryButton = NSButton(title: "Open account.apple.com", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let submitButton = NSButton(title: "Sign In", target: nil, action: nil)
    private var submitTask: Task<Void, Never>?

    init(
        model: MitoriModel,
        accountID: String,
        accountLabel: String,
        requiresCodeInitially: Bool,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.onDismiss = onDismiss
        flow.requiresVerificationCode = requiresCodeInitially
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

    override func viewDidAppear() {
        super.viewDidAppear()
        if flow.showsVerificationCode {
            view.window?.makeFirstResponder(codeField)
        } else {
            view.window?.makeFirstResponder(passwordField)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        submitTask?.cancel()
        submitTask = nil
    }

    func controlTextDidChange(_: Notification) {
        reload()
    }
}

private extension SignInAgainSheetController {
    func configureLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Sign In Again")
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "Sign in to \(accountLabel). Leave Password empty to use the saved password, or enter a new one if you changed it.")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        addFullWidth(header, to: root)

        passwordField.placeholderString = "Saved password"
        passwordField.font = .systemFont(ofSize: 13)
        passwordField.delegate = self
        passwordField.target = self
        passwordField.action = #selector(submit)
        passwordField.setAccessibilityIdentifier("account-detail.password")

        codeField.placeholderString = "6-digit verification code"
        codeField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        codeField.delegate = self
        codeField.target = self
        codeField.action = #selector(submit)
        codeField.setAccessibilityIdentifier("account-detail.code")

        let grid = NSGridView(views: [
            [formLabel("Password"), passwordField],
            [formLabel("Code"), codeField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowAlignment = .firstBaseline
        codeRow = grid.row(at: 1)
        addFullWidth(grid, to: root)

        guidanceLabel.font = .systemFont(ofSize: 11)
        guidanceLabel.textColor = .secondaryLabelColor
        guidanceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addFullWidth(guidanceLabel, to: root)

        errorLabel.font = .systemFont(ofSize: 11.5)
        errorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.setAccessibilityIdentifier("account-detail.error")
        addFullWidth(errorLabel, to: root)

        recoveryButton.bezelStyle = .inline
        recoveryButton.alignment = .left
        recoveryButton.target = self
        recoveryButton.action = #selector(openRecoveryLink)
        recoveryButton.setAccessibilityIdentifier("account-detail.recovery")
        root.addArrangedSubview(recoveryButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.setAccessibilityIdentifier("account-detail.reauth-cancel")

        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.setAccessibilityIdentifier("account-detail.reauthenticate-submit")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [spinner, spacer, cancelButton, submitButton])
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
            view.widthAnchor.constraint(equalToConstant: 400),
        ])
    }

    func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: "\(title):")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    func reload() {
        flow.password = passwordField.stringValue
        flow.verificationCode = codeField.stringValue

        let showCode = flow.showsVerificationCode
        codeRow?.isHidden = !showCode
        guidanceLabel.stringValue = showCode ? flow.twoFactorMessage : ""
        guidanceLabel.isHidden = !showCode

        let message = flow.errorMessage ?? ""
        errorLabel.stringValue = message
        errorLabel.isHidden = message.isEmpty

        recoveryButton.title = flow.recoveryLink?.title ?? "Open account.apple.com"
        recoveryButton.isHidden = flow.recoveryLink == nil

        submitButton.isEnabled = flow.canSubmit
        if flow.isSubmitting {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    @objc
    func submit() {
        reload()
        guard flow.canSubmit else { return }
        flow.beginSubmission()
        reload()

        let password = passwordField.stringValue.isEmpty ? nil : passwordField.stringValue
        let code = flow.verificationCode
        submitTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Auth succeeded and persisted; close even if the follow-up probe records an issue,
                // so the detail view displays the probe issue instead of trapping the user here.
                _ = try await model.reauthenticateAccount(
                    id: accountID,
                    password: password,
                    code: code
                )
                try Task.checkCancellation()
                flow.resetAfterSuccess()
                submitTask = nil
                onDismiss()
            } catch is CancellationError {
                flow.finishSubmission()
                submitTask = nil
                reload()
            } catch {
                flow.finishSubmission()
                submitTask = nil
                flow.handleFailure(error)
                reload()
                if flow.showsVerificationCode {
                    view.window?.makeFirstResponder(codeField)
                }
            }
        }
    }

    @objc
    func openRecoveryLink() {
        guard let url = flow.recoveryLink?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    func cancel() {
        submitTask?.cancel()
        submitTask = nil
        onDismiss()
    }
}
