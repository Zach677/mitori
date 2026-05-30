import AppKit

@MainActor
final class AddAccountViewController: NSViewController {
    private let model: MitoriModel
    private let onClose: () -> Void
    private let flow = AddAccountFlowModel()

    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let verificationCodeField = NSTextField()
    private let probeBundleIDField = NSTextField()
    private let twoFactorMessageLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let recoveryButton = NSButton(title: "Open account.apple.com", target: nil, action: nil)
    private let submitButton = NSButton(title: "Login", target: nil, action: nil)
    private let twoFactorSection = NSStackView()

    init(model: MitoriModel, onClose: @escaping () -> Void) {
        self.model = model
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

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(emailField)
    }
}

private extension AddAccountViewController {
    func configureLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 18, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(header)
        root.addArrangedSubview(makeCredentialsSection())
        root.addArrangedSubview(makeTwoFactorSection())
        root.addArrangedSubview(makeProbeSection())
        root.addArrangedSubview(makeErrorSection())
        root.addArrangedSubview(makeActionRow())

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 420),
        ])
    }

    var header: NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6

        let title = NSTextField(labelWithString: "Add Apple Account")
        title.font = .systemFont(ofSize: 16, weight: .medium)

        let subtitle = NSTextField(labelWithString: "Sign in with your Apple ID. If Apple asks for two-factor authentication, enter the code and submit again.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 3

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    func makeCredentialsSection() -> NSView {
        let stack = section(title: "Apple ID")
        emailField.placeholderString = "Email"
        emailField.target = self
        emailField.action = #selector(focusPassword)
        passwordField.placeholderString = "Password"
        passwordField.target = self
        passwordField.action = #selector(submit)
        stack.addArrangedSubview(emailField)
        stack.addArrangedSubview(passwordField)
        return stack
    }

    func makeTwoFactorSection() -> NSView {
        twoFactorSection.orientation = .vertical
        twoFactorSection.spacing = 8

        let title = fieldLabel("Two-Factor Authentication")
        twoFactorMessageLabel.font = .systemFont(ofSize: 12)
        twoFactorMessageLabel.textColor = .secondaryLabelColor
        twoFactorMessageLabel.maximumNumberOfLines = 3
        verificationCodeField.placeholderString = "Verification Code"
        verificationCodeField.target = self
        verificationCodeField.action = #selector(submit)

        twoFactorSection.addArrangedSubview(title)
        twoFactorSection.addArrangedSubview(twoFactorMessageLabel)
        twoFactorSection.addArrangedSubview(verificationCodeField)
        return twoFactorSection
    }

    func makeProbeSection() -> NSView {
        let stack = section(title: "Balance Probe")
        probeBundleIDField.placeholderString = "Owned app bundle ID"
        stack.addArrangedSubview(probeBundleIDField)

        let help = NSTextField(labelWithString: "Apple's balance API requires a bundle ID from an app this account owns. You can add it later.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.lineBreakMode = .byWordWrapping
        help.maximumNumberOfLines = 3
        stack.addArrangedSubview(help)
        return stack
    }

    func makeErrorSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 4

        recoveryButton.bezelStyle = .inline
        recoveryButton.alignment = .left
        recoveryButton.target = self
        recoveryButton.action = #selector(openRecoveryLink)

        stack.addArrangedSubview(errorLabel)
        stack.addArrangedSubview(recoveryButton)
        return stack
    }

    func makeActionRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded

        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"

        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(submitButton)
        return stack
    }

    func section(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.addArrangedSubview(fieldLabel(title))
        return stack
    }

    func fieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    func reload() {
        flow.email = emailField.stringValue
        flow.password = passwordField.stringValue
        flow.verificationCode = verificationCodeField.stringValue
        flow.probeBundleID = probeBundleIDField.stringValue

        twoFactorSection.isHidden = !flow.requiresVerificationCode
        twoFactorMessageLabel.stringValue = flow.twoFactorMessage
        errorLabel.stringValue = flow.errorMessage ?? ""
        errorLabel.isHidden = flow.errorMessage?.isEmpty ?? true
        recoveryButton.isHidden = flow.recoveryLink == nil
        submitButton.title = flow.requiresVerificationCode ? "Verify & Login" : "Login"
        submitButton.isEnabled = flow.canSubmit
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

        Task {
            do {
                try await model.addAccount(
                    email: flow.email,
                    password: flow.password,
                    code: flow.verificationCode,
                    deviceIdentifier: flow.deviceIdentifier,
                    probeBundleID: flow.probeBundleID
                )
                onClose()
            } catch {
                flow.handleFailure(error)
                reload()
                if flow.requiresVerificationCode {
                    view.window?.makeFirstResponder(verificationCodeField)
                }
            }
            flow.finishSubmission()
            reload()
        }
    }

    @objc
    func openRecoveryLink() {
        guard let url = flow.recoveryLink?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    func cancel() {
        onClose()
    }
}
