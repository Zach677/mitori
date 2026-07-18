import AppKit

@MainActor
final class AccountRowView: NSView {
    private let account: StoredAccountMeta
    private let refreshState: RefreshState
    private let onOpen: @MainActor () -> Void
    private let onRefresh: @MainActor () -> Void

    init(
        account: StoredAccountMeta,
        refreshState: RefreshState,
        onOpen: @escaping @MainActor () -> Void,
        onRefresh: @escaping @MainActor () -> Void
    ) {
        self.account = account
        self.refreshState = refreshState
        self.onOpen = onOpen
        self.onRefresh = onRefresh
        super.init(frame: .zero)
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
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 1
        identity.addArrangedSubview(label(account.displayName, size: 12, weight: .medium))
        identity.addArrangedSubview(label(account.email, size: 11, color: .secondaryLabelColor))

        let trailing = NSStackView()
        trailing.orientation = .vertical
        trailing.alignment = .trailing
        trailing.spacing = 1
        trailing.addArrangedSubview(balanceLabel)
        if let hint {
            trailing.addArrangedSubview(label(hint, size: 11, color: hintColor))
        }

        stack.addArrangedSubview(identity)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(trailing)
        stack.addArrangedSubview(makeActionButton())

        addSubview(stack)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(open)))
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private var balanceLabel: NSTextField {
        label(
            isRefreshing ? "…" : account.balanceDisplayText ?? "—",
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

    private func makeActionButton() -> NSButton {
        let button = NSButton()
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.controlSize = .small
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true

        if account.requiresProbeConfiguration {
            button.title = "Set Up"
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.isBordered = true
            button.bezelStyle = .rounded
            button.target = self
            button.action = #selector(open)
        } else {
            button.image = NSImage(
                systemSymbolName: isRefreshing ? "hourglass" : "arrow.clockwise",
                accessibilityDescription: "Refresh"
            )
            button.toolTip = "Refresh"
            button.target = self
            button.action = #selector(refresh)
            button.isEnabled = !isRefreshing
        }
        return button
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
