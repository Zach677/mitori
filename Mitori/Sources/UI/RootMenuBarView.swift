import Observation
import SwiftUI

struct RootMenuBarView: View {
    private enum PanelMetrics {
        static let width: CGFloat = 352
        static let maxScrollHeight: CGFloat = 480
    }

    @Bindable var model: MitoriModel
    let onAddAccount: () -> Void
    let onOpenAccount: (String) -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if model.accounts.isEmpty {
                emptyState
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.accounts) { account in
                            AccountRowView(
                                account: account,
                                refreshState: model.refreshState(for: account.id),
                                onOpen: { onOpenAccount(account.id) },
                                onRefresh: {
                                    Task {
                                        await model.refreshAccount(id: account.id, isManualRefresh: true)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: PanelMetrics.maxScrollHeight)
            }

            if let bannerMessage = model.bannerMessage, !bannerMessage.isEmpty {
                Text(bannerMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: PanelMetrics.width)
        .task {
            await model.menuPresented()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard.and.123")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Mitori")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    Task {
                        await model.refreshAll()
                    }
                } label: {
                    Image(systemName: model.isRefreshingAll ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.accounts.isEmpty || model.isRefreshingAll)

                Button {
                    onAddAccount()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No accounts yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add an Apple ID to start tracking balances.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAddAccount()
            } label: {
                Text("Add Account")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Text(summaryText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                onQuit()
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryText: String {
        let count = model.accounts.count
        guard count > 0 else { return "" }
        let refreshedAt = model.accounts.compactMap(\.lastRefreshAt).max()
        let refreshLabel = refreshedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never"
        return "\(count) account\(count == 1 ? "" : "s") · \(refreshLabel)"
    }
}

private struct AccountRowView: View {
    let account: StoredAccountMeta
    let refreshState: RefreshState
    let onOpen: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    accountAvatar

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        Text(account.email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    statusBadge
                }
                .padding(.bottom, 8)

                Divider()
                    .padding(.bottom, 8)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.balanceSnapshot?.displayText ?? "—")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)

                        if let region = regionText {
                            Text(region)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 8)

                    refreshButton
                }

                if let warningText {
                    Text(warningText)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    private var accountAvatar: some View {
        Text(avatarInitial)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(avatarColor.gradient, in: RoundedRectangle(cornerRadius: 7))
    }

    private var avatarInitial: String {
        let name = account.displayName
        return String(name.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        let hash = abs(account.email.hashValue)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return colors[hash % colors.count]
    }

    private var regionText: String? {
        let label = account.regionLabel
        return label.isEmpty ? nil : label
    }

    private var warningText: String? {
        if account.requiresProbeConfiguration {
            return "Needs an owned app bundle ID to refresh balance."
        } else if let issue = account.lastIssue {
            return issue.message
        }
        return nil
    }

    @ViewBuilder
    private var refreshButton: some View {
        if account.requiresProbeConfiguration {
            Button("Configure", action: onOpen)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
        } else {
            Button {
                onRefresh()
            } label: {
                if case .refreshing = refreshState {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)

            Text(statusTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusTint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(statusTint.opacity(0.1), in: Capsule())
    }

    private var statusTitle: String {
        if case .refreshing = refreshState {
            return "Syncing"
        }

        switch account.status {
        case .normal:
            return "OK"
        case .needsVerification:
            return "2FA"
        case .sessionExpired:
            return "Expired"
        case .attention:
            return "Attention"
        }
    }

    private var statusTint: Color {
        if case .refreshing = refreshState {
            return .blue
        }

        switch account.status {
        case .normal:
            return .green
        case .needsVerification:
            return .orange
        case .sessionExpired:
            return .red
        case .attention:
            return .yellow
        }
    }
}
