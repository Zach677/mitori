//
//  AddAccountViewController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/05/30.
//

import AppKit

@MainActor
final class AddAccountViewController: NSViewController, NSTextFieldDelegate {
    private let model: MitoriModel
    private let onClose: @MainActor () -> Void
    private let onLoginSuccess: @MainActor (String) -> Void
    private let flow = AddAccountFlowModel()

    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let verificationCodeField = NSTextField()
    private var codeRow: NSGridRow?
    private let twoFactorMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let recoveryButton = NSButton(title: "Open account.apple.com", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let submitButton = NSButton(title: "Sign In", target: nil, action: nil)
    private var loginTask: Task<Void, Never>?

    init(
        model: MitoriModel,
        onClose: @escaping @MainActor () -> Void,
        onLoginSuccess: @escaping @MainActor (String) -> Void
    ) {
        self.model = model
        self.onClose = onClose
        self.onLoginSuccess = onLoginSuccess
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
        view.window?.makeFirstResponder(emailField)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        cancelLogin()
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
    }

    func controlTextDidChange(_: Notification) {
        reload()
    }
}

private extension AddAccountViewController {
    func configureLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Add Apple Account")
        title.font = .systemFont(ofSize: 13, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: "Sign in with your Apple ID. If Apple asks for two-factor authentication, enter the code and sign in again.")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        addFullWidth(header, to: root)

        configureField(emailField, placeholder: "name@example.com")
        emailField.target = self
        emailField.action = #selector(focusPassword)
        emailField.setAccessibilityIdentifier("add-account.email")

        configureField(passwordField, placeholder: "Password")
        passwordField.target = self
        passwordField.action = #selector(submit)
        passwordField.setAccessibilityIdentifier("add-account.password")

        configureField(verificationCodeField, placeholder: "6-digit code")
        verificationCodeField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        verificationCodeField.target = self
        verificationCodeField.action = #selector(submit)
        verificationCodeField.setAccessibilityIdentifier("add-account.code")

        let grid = NSGridView(views: [
            [formLabel("Apple ID"), emailField],
            [formLabel("Password"), passwordField],
            [formLabel("Code"), verificationCodeField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowAlignment = .firstBaseline
        codeRow = grid.row(at: 2)
        addFullWidth(grid, to: root)

        twoFactorMessageLabel.font = .systemFont(ofSize: 11)
        twoFactorMessageLabel.textColor = .secondaryLabelColor
        twoFactorMessageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addFullWidth(twoFactorMessageLabel, to: root)

        errorLabel.font = .systemFont(ofSize: 11.5)
        errorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.setAccessibilityIdentifier("add-account.error")
        addFullWidth(errorLabel, to: root)

        recoveryButton.bezelStyle = .inline
        recoveryButton.alignment = .left
        recoveryButton.target = self
        recoveryButton.action = #selector(openRecoveryLink)
        recoveryButton.setAccessibilityIdentifier("add-account.recovery")
        root.addArrangedSubview(recoveryButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.setAccessibilityIdentifier("add-account.cancel")

        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.setAccessibilityIdentifier("add-account.submit")

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
            view.widthAnchor.constraint(equalToConstant: 420),
        ])
    }

    func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: "\(title):")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    func configureField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.delegate = self
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 13)
    }

    func reload() {
        flow.email = emailField.stringValue
        flow.password = passwordField.stringValue
        if verificationCodeField.stringValue != flow.verificationCode,
           flow.verificationCode.isEmpty,
           !flow.showsVerificationCode
        {
            verificationCodeField.stringValue = ""
        } else {
            flow.verificationCode = verificationCodeField.stringValue
        }

        codeRow?.isHidden = !flow.showsVerificationCode
        twoFactorMessageLabel.stringValue = flow.showsVerificationCode ? flow.twoFactorMessage : ""
        twoFactorMessageLabel.isHidden = !flow.showsVerificationCode

        let errorText = flow.errorMessage ?? ""
        errorLabel.stringValue = errorText
        errorLabel.isHidden = errorText.isEmpty

        recoveryButton.title = flow.recoveryLink?.title ?? "Open account.apple.com"
        recoveryButton.isHidden = flow.recoveryLink == nil

        submitButton.title = "Sign In"
        submitButton.isEnabled = flow.canSubmit
        if flow.isSubmitting {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    @objc
    func focusPassword() {
        view.window?.makeFirstResponder(passwordField)
    }

    @objc
    func submit() {
        reload()
        guard flow.canSubmit else { return }

        flow.beginSubmission()
        reload()

        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let accountID = try await model.addAccount(
                    email: flow.email,
                    password: flow.password,
                    code: flow.verificationCode,
                    deviceIdentifier: flow.deviceIdentifier,
                    probeBundleID: ""
                )
                try Task.checkCancellation()
                flow.finishSubmission()
                loginTask = nil
                onLoginSuccess(accountID)
            } catch {
                flow.finishSubmission()
                loginTask = nil
                guard !Task.isCancelled else { return }
                flow.handleFailure(error)
                reload()
                if flow.showsVerificationCode {
                    view.window?.makeFirstResponder(verificationCodeField)
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
        cancelLogin()
        onClose()
    }
}
