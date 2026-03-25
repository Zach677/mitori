import SwiftUI

struct AccountDetailSheet: View {
    let model: MitoriModel
    let accountID: String

    @Environment(\.dismiss) private var dismiss

    @State private var probeBundleID = ""
    @State private var verificationCode = ""
    @State private var errorMessage: String?
    @State private var isSavingProbe = false
    @State private var isReauthing = false
    @State private var isDeleting = false

    private var account: StoredAccountMeta? {
        model.account(with: accountID)
    }

    var body: some View {
        NavigationStack {
            if let account {
                Form {
                    Section("Account") {
                        detailRow("Email", value: account.email)
                        detailRow("Apple ID", value: account.appleID)
                        detailRow("Region", value: account.regionLabel.isEmpty ? "Unknown" : account.regionLabel)
                        detailRow("Pod", value: account.pod ?? "Unavailable")
                        detailRow("DSID", value: model.secretSummary(for: accountID))
                        detailRow("Device ID", value: account.deviceIdentifier)
                    }

                    Section("Balance") {
                        detailRow("Last Balance", value: account.balanceSnapshot?.displayText ?? "Unavailable")
                        detailRow(
                            "Last Success",
                            value: account.lastRefreshAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                        )
                    }

                    Section("Probe Bundle ID") {
                        TextField("Owned app bundle ID", text: $probeBundleID)
                        Button("Save Probe Bundle ID") {
                            saveProbeBundleID()
                        }
                        .disabled(isSavingProbe)
                    }

                    Section("Re-authentication") {
                        TextField("2FA Code (optional)", text: $verificationCode)
                        Button("Re-authenticate") {
                            reauthenticate()
                        }
                        .disabled(isReauthing)
                    }

                    Section("Actions") {
                        Button("Refresh Balance") {
                            refreshBalance()
                        }

                        Button(role: .destructive) {
                            deleteAccount()
                        } label: {
                            if isDeleting {
                                ProgressView()
                            } else {
                                Text("Delete Account")
                            }
                        }
                        .disabled(isDeleting)
                    }

                    if let errorMessage {
                        Section("Error") {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(account.displayName)
                .task {
                    probeBundleID = account.probeBundleID
                    await model.loadSecretSummary(for: accountID)
                }
            } else {
                ContentUnavailableView("Account removed", systemImage: "trash")
            }
        }
        .frame(width: 440, height: 500)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

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
            dismiss()
        }
    }
}
