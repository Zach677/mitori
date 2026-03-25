import Observation
import SwiftUI

struct RootMenuBarView: View {
    @Bindable var model: MitoriModel
    let onAddAccount: () -> Void
    let onOpenAccount: (String) -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if model.accounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
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
                }
                .frame(maxHeight: 420)
            }

            if let bannerMessage = model.bannerMessage, !bannerMessage.isEmpty {
                Text(bannerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Quit", action: onQuit)
            }
        }
        .padding(16)
        .frame(width: 420)
        .task {
            await model.menuPresented()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mitori")
                    .font(.headline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    await model.refreshAll()
                }
            } label: {
                Label("Refresh All", systemImage: model.isRefreshingAll ? "hourglass" : "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(model.accounts.isEmpty || model.isRefreshingAll)

            Button {
                onAddAccount()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No accounts yet")
                .font(.headline)
            Text("Add an Apple ID, then give the app one owned bundle ID if balance probing needs it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add Account") {
                onAddAccount()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var summaryText: String {
        let count = model.accounts.count
        let refreshedAt = model.accounts.compactMap(\.lastRefreshAt).max()
        let refreshLabel = refreshedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never"
        return "\(count) account\(count == 1 ? "" : "s") • latest \(refreshLabel)"
    }
}

private struct AccountRowView: View {
    let account: StoredAccountMeta
    let refreshState: RefreshState
    let onOpen: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.email)
                        .font(.headline)
                        .textSelection(.enabled)
                    if !account.regionLabel.isEmpty {
                        Text(account.regionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusBadge
            }

            Text(account.balanceSnapshot?.displayText ?? "Balance unavailable")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()

            if let issue = account.lastIssue {
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if account.probeBundleID.isEmpty {
                Text("Probe bundle ID missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Details", action: onOpen)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    if case .refreshing = refreshState {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(statusTint)
            .background(statusTint.opacity(0.12), in: Capsule())
    }

    private var statusTitle: String {
        if case .refreshing = refreshState {
            return "Refreshing"
        }

        switch account.status {
        case .normal:
            return "Normal"
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
