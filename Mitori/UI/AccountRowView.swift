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

    private let account: StoredAccountMeta
    private let presentation: AccountPresentation
    private let refreshState: RefreshState
    private let onOpen: @MainActor () -> Void
    private let onRefresh: @MainActor () -> Void
    private weak var actionButton: NSButton?
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = Metrics.lineSpacing
        identity.addArrangedSubview(label(presentation.name, size: 13, weight: .medium))
        if let email = presentation.email {
            identity.addArrangedSubview(label(email, size: 12, color: .secondaryLabelColor))
        }

        let trailing = NSStackView()
        trailing.orientation = .vertical
        trailing.alignment = .trailing
        trailing.spacing = Metrics.lineSpacing
        trailing.addArrangedSubview(balanceLabel)
        if let hint {
            trailing.addArrangedSubview(label(hint, size: 11, color: hintColor))
        }

        stack.addArrangedSubview(identity)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(trailing)
        stack.addArrangedSubview(makeActionView())

        addSubview(stack)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open \(presentation.name)")
        setAccessibilityHelp("Open account details")
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
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
        if let actionButton {
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

    private var balanceLabel: NSTextField {
        label(
            account.balanceDisplayText ?? "—",
            size: 15,
            weight: .medium,
            monospaced: true
        )
    }

    private var hint: String? {
        if isRefreshing { return nil }
        if account.requiresProbeConfiguration { return "Set up probe app" }
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

    private func makeActionView() -> NSView {
        if account.requiresProbeConfiguration {
            return makeActionButton(title: "Set Up", action: #selector(open))
        }
        if isRefreshing {
            return makeProgressIndicator()
        }
        return makeActionButton(action: #selector(refresh))
    }

    private func makeActionButton(title: String? = nil, action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(
            equalToConstant: title == nil ? Metrics.actionWidth : 54
        ).isActive = true

        if let title {
            button.title = title
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.isBordered = true
            button.bezelStyle = .rounded
        } else {
            button.imagePosition = .imageOnly
            button.image = NSImage(
                systemSymbolName: "arrow.clockwise",
                accessibilityDescription: "Refresh"
            )
            button.toolTip = "Refresh"
        }
        button.target = self
        button.action = action
        actionButton = button
        return button
    }

    private func makeProgressIndicator() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: Metrics.actionWidth).isActive = true

        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.setAccessibilityLabel("Refreshing balance")
        progress.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            progress.widthAnchor.constraint(equalToConstant: 14),
            progress.heightAnchor.constraint(equalToConstant: 14),
        ])
        progress.startAnimation(nil)
        return wrapper
    }

    private var interactionBounds: NSRect {
        bounds.insetBy(dx: 8, dy: 2)
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        monospaced: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    @objc
    private func open() {
        onOpen()
    }

    @objc
    private func refresh() {
        onRefresh()
    }
}
