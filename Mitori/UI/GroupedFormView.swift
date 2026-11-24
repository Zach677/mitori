//
//  GroupedFormView.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/24.
//

import AppKit

/// Native macOS System Settings-style grouped box (`quaternarySystemFill`, 10 pt corner radius,
/// 0.5 pt separator border, inset horizontal dividers).
@MainActor
final class GroupedFormView: NSView {
    private let outerStack = NSStackView()
    private let cardView = GroupedCardContainer()
    private let rowsStack = NSStackView()

    init(title: String? = nil, footnote: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        outerStack.orientation = .vertical
        outerStack.alignment = .width
        outerStack.spacing = 6
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let title, !title.isEmpty {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            let wrapper = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
            outerStack.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true
        }

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: cardView.topAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])
        outerStack.addArrangedSubview(cardView)
        cardView.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true

        if let footnote, !footnote.isEmpty {
            let label = NSTextField(wrappingLabelWithString: footnote)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let wrapper = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: wrapper.topAnchor),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])
            outerStack.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addRow(_ rowView: NSView, minHeight: CGFloat = 36) {
        if !rowsStack.arrangedSubviews.isEmpty {
            let separator = makeInsetSeparator()
            rowsStack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        let container = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            rowView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            rowView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            rowView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
        ])
        rowsStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
    }

    /// Hides a row added with `addRow` together with its separator.
    func setRowHidden(_ rowView: NSView, _ hidden: Bool) {
        guard let container = rowView.superview,
              let index = rowsStack.arrangedSubviews.firstIndex(of: container) else { return }
        container.isHidden = hidden
        let separatorIndex = index > 0 ? index - 1 : index + 1
        if rowsStack.arrangedSubviews.indices.contains(separatorIndex) {
            rowsStack.arrangedSubviews[separatorIndex].isHidden = hidden
        }
    }

    func clearRows() {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func makeInsetSeparator() -> NSView {
        let wrapper = NSView()
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            wrapper.heightAnchor.constraint(equalToConstant: 1),
        ])
        return wrapper
    }
}

@MainActor
private final class GroupedCardContainer: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        }
    }
}

/// Pure presentation mapping for an account's visible issue (spec §4, §5, I-3, I-9, I-10).
struct AccountIssuePresentation: Equatable {
    enum Tone: Equatable {
        case danger
        case warning
        case neutral
    }

    enum Action: Equatable {
        case signInAgain(requiresCode: Bool)
        case chooseApp
        case refresh
    }

    let sidebarHint: String?
    let detailTitle: String
    let message: String
    let metadata: String
    let symbolName: String
    let tone: Tone
    let action: Action?
    let actionTitle: String?

    init?(account: StoredAccountMeta, nextAutoRefreshAt: Date?) {
        guard let issue = account.visibleIssue else { return nil }
        message = issue.message
        let sinceText = issue.updatedAt.shortTimestamp()

        switch issue.kind {
        case .sessionExpired:
            sidebarHint = "Session expired"
            detailTitle = "Session expired"
            metadata = "Since \(sinceText) · Automatic refresh paused"
            symbolName = "lock.fill"
            tone = .danger
            action = .signInAgain(requiresCode: false)
            actionTitle = "Sign In Again…"

        case .requiresVerification:
            sidebarHint = "Code needed"
            detailTitle = "Verification code needed"
            metadata = "Since \(sinceText) · Automatic refresh paused"
            symbolName = "lock.fill"
            tone = .warning
            action = .signInAgain(requiresCode: true)
            actionTitle = "Enter Code…"

        case .probeConfigurationMissing:
            sidebarHint = "Refresh app missing"
            detailTitle = "Background refresh app unavailable"
            metadata = "Since \(sinceText) · Automatic refresh paused"
            symbolName = "app.badge"
            tone = .warning
            action = .chooseApp
            actionTitle = "Choose App…"

        case .balanceUnavailable:
            sidebarHint = "No balance data"
            detailTitle = "No balance data"
            metadata = "Since \(sinceText) · Automatic refresh paused"
            symbolName = "exclamationmark.triangle.fill"
            tone = .warning
            action = .refresh
            actionTitle = "Refresh"

        case .network:
            sidebarHint = nil
            detailTitle = "Couldn't reach Apple"
            symbolName = "wifi.exclamationmark"
            tone = .neutral
            if let nextAutoRefreshAt {
                let retryTime = nextAutoRefreshAt.formatted(date: .omitted, time: .shortened)
                metadata = "Since \(sinceText) · Mitori will try again at \(retryTime)"
                action = nil
                actionTitle = nil
            } else {
                metadata = "Since \(sinceText)"
                action = .refresh
                actionTitle = "Refresh"
            }

        case .unknown:
            sidebarHint = "Needs attention"
            detailTitle = "Needs attention"
            metadata = "Since \(sinceText) · Automatic refresh paused"
            symbolName = "exclamationmark.triangle.fill"
            tone = .warning
            action = .refresh
            actionTitle = "Refresh"
        }
    }

    @MainActor
    var tintColor: NSColor {
        switch tone {
        case .danger:
            return NSColor.systemRed.blended(withFraction: 0.25, of: .labelColor) ?? .systemRed
        case .warning:
            return NSColor.systemOrange.blended(withFraction: 0.3, of: .labelColor) ?? .systemOrange
        case .neutral:
            return .secondaryLabelColor
        }
    }
}
