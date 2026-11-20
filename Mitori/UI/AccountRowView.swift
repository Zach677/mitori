import AppKit

@MainActor
final class AccountRowView: NSView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 12
        static let itemSpacing: CGFloat = 8
        static let lineSpacing: CGFloat = 2
        static let actionWidth: CGFloat = 24
    }

    private var account: StoredAccountMeta
    private var presentation: AccountPresentation
    private var refreshState: RefreshState
    private let onOpen: @MainActor () -> Void
    private let onRefresh: @MainActor () -> Void

    private let nameLabel = NSTextField(labelWithString: "")
    private let emailLabel = NSTextField(labelWithString: "")
    private let balanceLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private let progressWrapper = NSView()
    private let progressIndicator = NSProgressIndicator()

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    init(
        account: StoredAccountMeta,
        presentation: AccountPresentation,
        refreshState: RefreshState,
        onOpen: @escaping @MainActor () -> Void,
        onRefresh: @escaping @MainActor () -> Void
    ) {
        self.account = account
        self.presentation = presentation
        self.refreshState = refreshState
        self.onOpen = onOpen
        self.onRefresh = onRefresh
        super.init(frame: .zero)
        focusRingType = .default
        configure()
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        account: StoredAccountMeta,
        presentation: AccountPresentation,
        refreshState: RefreshState
    ) {
        self.account = account
        self.presentation = presentation
        self.refreshState = refreshState
        applyState()
    }

    private func configure() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.itemSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: Metrics.verticalInset,
            left: Metrics.horizontalInset,
            bottom: Metrics.verticalInset,
            right: Metrics.horizontalInset
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        configureLabel(nameLabel, size: 13, weight: .medium)
        configureLabel(emailLabel, size: 12, color: .secondaryLabelColor)
        configureLabel(balanceLabel, size: 15, weight: .medium, monospaced: true)
        configureLabel(hintLabel, size: 11, color: .secondaryLabelColor)

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = Metrics.lineSpacing
        identity.addArrangedSubview(nameLabel)
        identity.addArrangedSubview(emailLabel)

        let trailing = NSStackView()
        trailing.orientation = .vertical
        trailing.alignment = .trailing
        trailing.spacing = Metrics.lineSpacing
        trailing.addArrangedSubview(balanceLabel)
        trailing.addArrangedSubview(hintLabel)

        configureActionButton()
        configureProgressIndicator()

        stack.addArrangedSubview(identity)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(trailing)
        stack.addArrangedSubview(actionButton)
        stack.addArrangedSubview(progressWrapper)

        addSubview(stack)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Open account details")
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func applyState() {
        nameLabel.stringValue = presentation.name
        if let email = presentation.email {
            emailLabel.stringValue = email
            emailLabel.isHidden = false
        } else {
            emailLabel.stringValue = ""
            emailLabel.isHidden = true
        }

        balanceLabel.stringValue = account.balanceDisplayText ?? "—"

        let currentHint = hint
        if let currentHint {
            hintLabel.stringValue = currentHint
            hintLabel.textColor = hintColor
            hintLabel.isHidden = false
        } else {
            hintLabel.stringValue = ""
            hintLabel.isHidden = true
        }

        let refreshing = isRefreshing
        actionButton.isHidden = refreshing
        actionButton.setAccessibilityIdentifier("account-row.\(account.id).refresh")
        progressWrapper.isHidden = !refreshing
        progressIndicator.setAccessibilityIdentifier("account-row.\(account.id).progress")
        if refreshing {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }

        setAccessibilityLabel("Open \(presentation.name)")
        setAccessibilityValue([account.balanceDisplayText ?? "No balance", currentHint].compactMap { $0 }.joined(separator: ", "))
        setAccessibilityIdentifier("account-row.\(account.id)")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var focusRingMaskBounds: NSRect {
        interactionBounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: interactionBounds, xRadius: 7, yRadius: 7).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color: NSColor? = if isPressed {
            .selectedContentBackgroundColor.withAlphaComponent(0.18)
        } else if isHovered {
            .labelColor.withAlphaComponent(0.06)
        } else {
            nil
        }
        if let color {
            color.setFill()
            NSBezierPath(roundedRect: interactionBounds, xRadius: 7, yRadius: 7).fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard !isHidden, alphaValue > 0, bounds.contains(localPoint) else { return nil }
        if !actionButton.isHidden, actionButton.superview != nil {
            let actionPoint = actionButton.convert(localPoint, from: self)
            if actionButton.bounds.contains(actionPoint) {
                return actionButton
            }
        }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let shouldOpen = isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if shouldOpen {
            onOpen()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat,
              event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == " "
        else {
            super.keyDown(with: event)
            return
        }
        onOpen()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        needsDisplay = true
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        needsDisplay = true
        return resignedFirstResponder
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen()
        return true
    }

    private var hint: String? {
        if isRefreshing { return nil }
        switch account.status {
        case .normal:
            return nil
        case .needsVerification:
            return "2FA required"
        case .sessionExpired:
            return "Session expired"
        case .attention:
            return "Needs attention"
        }
    }

    private var hintColor: NSColor {
        switch account.status {
        case .sessionExpired:
            return NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        default:
            return NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange
        }
    }

    private var isRefreshing: Bool {
        if case .refreshing = refreshState {
            return true
        }
        return false
    }

    private func configureActionButton() {
        actionButton.isBordered = false
        actionButton.controlSize = .small
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.widthAnchor.constraint(equalToConstant: Metrics.actionWidth).isActive = true
        actionButton.imagePosition = .imageOnly
        actionButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Refresh"
        )
        actionButton.toolTip = "Refresh"
        actionButton.target = self
        actionButton.action = #selector(refresh)
    }

    private func configureProgressIndicator() {
        progressWrapper.translatesAutoresizingMaskIntoConstraints = false
        progressWrapper.widthAnchor.constraint(equalToConstant: Metrics.actionWidth).isActive = true

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.setAccessibilityLabel("Refreshing balance")
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressWrapper.addSubview(progressIndicator)
        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: progressWrapper.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: progressWrapper.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 14),
            progressIndicator.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private var interactionBounds: NSRect {
        bounds.insetBy(dx: 8, dy: 2)
    }

    private func configureLabel(
        _ field: NSTextField,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        monospaced: Bool = false
    ) {
        field.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
    }

    @objc
    private func refresh() {
        onRefresh()
    }
}
