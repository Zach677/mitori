import AppKit

@MainActor
final class AddAccountViewController: NSViewController, NSTextFieldDelegate {
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
    private let errorSection = NSStackView()

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
        root.alignment = .width
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        addFullWidth(header, to: root)
        addFullWidth(makeCredentialsSection(), to: root)
        addFullWidth(makeTwoFactorSection(), to: root)
        addFullWidth(makeProbeSection(), to: root)
        addFullWidth(makeErrorSection(), to: root)
        root.addArrangedSubview(NSView())
        addFullWidth(makeActionRow(), to: root)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            view.widthAnchor.constraint(equalToConstant: 430),
        ])
    }

    var header: NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 12

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
        ])

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .width
        textStack.spacing = 5
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let title = NSTextField(labelWithString: "Add Apple Account")
        title.font = .systemFont(ofSize: 16, weight: .medium)
        title.alignment = .left

        let subtitle = NSTextField(labelWithString: "Sign in with your Apple ID. If Apple asks for two-factor authentication, enter the code and submit again.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.alignment = .left
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 3
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addFullWidth(title, to: textStack)
        addFullWidth(subtitle, to: textStack)
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(textStack)
        textStack.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -42).isActive = true
        return stack
    }

    func makeCredentialsSection() -> NSView {
        let stack = section(title: "Apple ID")
        configureField(emailField, placeholder: "Email")
        configureField(passwordField, placeholder: "Password")
        emailField.placeholderString = "Email"
        emailField.target = self
        emailField.action = #selector(focusPassword)
        passwordField.target = self
        passwordField.action = #selector(submit)
        addFullWidth(emailField, to: stack)
        addFullWidth(passwordField, to: stack)
        return stack
    }

    func makeTwoFactorSection() -> NSView {
        twoFactorSection.orientation = .vertical
        twoFactorSection.alignment = .width
        twoFactorSection.spacing = 8

        let title = fieldLabel("Two-Factor Authentication")
        twoFactorMessageLabel.font = .systemFont(ofSize: 12)
        twoFactorMessageLabel.textColor = .secondaryLabelColor
        twoFactorMessageLabel.maximumNumberOfLines = 3
        twoFactorMessageLabel.lineBreakMode = .byWordWrapping
        configureField(verificationCodeField, placeholder: "Verification Code")
        verificationCodeField.target = self
        verificationCodeField.action = #selector(submit)

        addFullWidth(title, to: twoFactorSection)
        addFullWidth(twoFactorMessageLabel, to: twoFactorSection)
        addFullWidth(verificationCodeField, to: twoFactorSection)
        return twoFactorSection
    }

    func makeProbeSection() -> NSView {
        let stack = section(title: "Balance Probe")
        configureField(probeBundleIDField, placeholder: "Owned app bundle ID")
        addFullWidth(probeBundleIDField, to: stack)

        let help = NSTextField(labelWithString: "Balance refresh needs a bundle ID from an app this account owns. You can add it later.")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        help.lineBreakMode = .byWordWrapping
        help.maximumNumberOfLines = 3
        help.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addFullWidth(help, to: stack)
        return stack
    }

    func makeErrorSection() -> NSView {
        errorSection.orientation = .vertical
        errorSection.alignment = .width
        errorSection.spacing = 6

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = NSColor.systemRed.blended(withFraction: 0.15, of: .labelColor)
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 4
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        recoveryButton.bezelStyle = .inline
        recoveryButton.alignment = .left
        recoveryButton.target = self
        recoveryButton.action = #selector(openRecoveryLink)

        addFullWidth(errorLabel, to: errorSection)
        errorSection.addArrangedSubview(recoveryButton)
        return errorSection
    }

    func makeActionRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded

        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"

        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(submitButton)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return stack
    }

    func section(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        addFullWidth(fieldLabel(title), to: stack)
        return stack
    }

    func fieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    func configureField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.delegate = self
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 13)
    }

    func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        let horizontalInsets = stack.edgeInsets.left + stack.edgeInsets.right
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -horizontalInsets).isActive = true
    }

    func reload() {
        flow.email = emailField.stringValue
        flow.password = passwordField.stringValue
        flow.verificationCode = verificationCodeField.stringValue
        flow.probeBundleID = probeBundleIDField.stringValue

        twoFactorSection.isHidden = !flow.requiresVerificationCode
        twoFactorMessageLabel.stringValue = flow.twoFactorMessage
        errorLabel.stringValue = flow.errorMessage ?? ""
        errorSection.isHidden = flow.errorMessage?.isEmpty ?? true
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

extension AddAccountViewController {
    func controlTextDidChange(_: Notification) {
        reload()
    }
}
