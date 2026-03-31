import Observation
import SwiftUI

struct AccountDetailSheet: View {
    let model: MitoriModel
    let accountID: String
    let onClose: () -> Void

    @State private var probeBundleID = ""
    @State private var verificationCode = ""
    @State private var errorMessage: String?
    @State private var probeLookup = ProbeAppLookupModel()
    @State private var isSavingProbe = false
    @State private var isReauthing = false
    @State private var isDeleting = false

    private var account: StoredAccountMeta? {
        model.account(with: accountID)
    }

    var body: some View {
        @Bindable var probeLookup = probeLookup

        NavigationStack {
            if let account {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        accountHeader(account)
                        balanceCard(account)
                        accountInfoSection(account)
                        probeSection
                        reauthSection
                        actionsSection

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                    .padding(20)
                }
                .navigationTitle(account.displayName)
                .task {
                    probeBundleID = account.probeBundleID
                    await model.loadSecretSummary(for: accountID)
                }
            } else {
                ContentUnavailableView("Account removed", systemImage: "trash")
            }
        }
        .frame(width: 440, height: 540)
    }

    private func accountHeader(_ account: StoredAccountMeta) -> some View {
        HStack(spacing: 12) {
            Text(String(account.displayName.prefix(1)).uppercased())
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(avatarColor(for: account).gradient, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(account.email)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }

    private func balanceCard(_ account: StoredAccountMeta) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Balance")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(account.balanceSnapshot?.displayText ?? "Unavailable")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()

            if let lastRefresh = account.lastRefreshAt {
                Text("Updated \(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func accountInfoSection(_ account: StoredAccountMeta) -> some View {
        detailSection("Account Info") {
            VStack(spacing: 0) {
                detailRow("Apple ID", value: account.appleID)
                detailDivider
                detailRow("Region", value: account.regionLabel.isEmpty ? "Unknown" : account.regionLabel)
                detailDivider
                detailRow("Pod", value: account.pod ?? "Unavailable")
                detailDivider
                detailRow("DSID", value: model.secretSummary(for: accountID))
                detailDivider
                detailRow("Device ID", value: String(account.deviceIdentifier.prefix(12)) + "…")
            }
        }
    }

    @ViewBuilder
    private var probeSection: some View {
        @Bindable var probeLookup = probeLookup

        detailSection("Probe Bundle ID") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Owned app bundle ID", text: $probeBundleID)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    TextField("Search app name", text: $probeLookup.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { searchProbeApps() }

                    Button {
                        searchProbeApps()
                    } label: {
                        if probeLookup.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!probeLookup.canSearch)
                }

                if let searchError = probeLookup.errorMessage {
                    Text(searchError)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if !probeLookup.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(probeLookup.results.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { Divider() }

                            Button {
                                probeBundleID = probeLookup.select(result)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.name)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(result.bundleID)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.blue)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }

                Text("Pick any app this Apple ID already owns.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Button("Save") {
                    saveProbeBundleID()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSavingProbe)
            }
        }
    }

    private var reauthSection: some View {
        detailSection("Re-authentication") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("2FA Code (optional)", text: $verificationCode)
                    .textFieldStyle(.roundedBorder)

                Button("Re-authenticate") {
                    reauthenticate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isReauthing)
            }
        }
    }

    private var actionsSection: some View {
        detailSection("Actions") {
            HStack(spacing: 8) {
                Button {
                    refreshBalance()
                } label: {
                    Label("Refresh Balance", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive) {
                    deleteAccount()
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDeleting)
            }
        }
    }

    // MARK: - Helpers

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            Text(value)
                .font(.system(size: 12))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }

    private var detailDivider: some View {
        Divider().opacity(0.5)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func avatarColor(for account: StoredAccountMeta) -> Color {
        let hash = abs(account.email.hashValue)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return colors[hash % colors.count]
    }

    // MARK: - Actions

    private func saveProbeBundleID() {
        guard !isSavingProbe else { return }

        isSavingProbe = true
        errorMessage = nil

        Task {
            do {
                try await model.saveProbeBundleID(probeBundleID, for: accountID)
            } catch {
                errorMessage = MitoriError.map(error).localizedDescription
            }
            isSavingProbe = false
        }
    }

    private func refreshBalance() {
        Task {
            await model.refreshAccount(id: accountID, isManualRefresh: true)
            errorMessage = model.account(with: accountID)?.lastIssue?.message
        }
    }

    private func reauthenticate() {
        guard !isReauthing else { return }

        isReauthing = true
        errorMessage = nil

        Task {
            do {
                try await model.reauthenticateAccount(id: accountID, code: verificationCode)
                verificationCode = ""
            } catch {
                errorMessage = MitoriError.map(error).localizedDescription
            }
            isReauthing = false
        }
    }

    private func deleteAccount() {
        guard !isDeleting else { return }

        isDeleting = true
        Task {
            await model.deleteAccount(id: accountID)
            onClose()
        }
    }

    private func searchProbeApps() {
        guard let account else { return }

        Task {
            await probeLookup.search(countryCode: account.countryCode)
        }
    }
}
