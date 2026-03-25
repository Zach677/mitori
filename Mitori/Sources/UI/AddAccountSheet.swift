import SwiftUI

struct AddAccountSheet: View {
    let model: MitoriModel
    let onClose: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var probeBundleID = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple ID") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                    SecureField("Password", text: $password)
                    TextField("2FA Code (optional)", text: $verificationCode)
                }

                Section("Balance Probe") {
                    TextField("Owned app bundle ID", text: $probeBundleID)
                    Text("Optional during login, but live balance refresh is much better with one owned bundle ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onClose()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Authenticate") {
                        submit()
                    }
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 340)
    }

    private func submit() {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await model.addAccount(
                    email: email,
                    password: password,
                    code: verificationCode,
                    probeBundleID: probeBundleID
                )
                onClose()
            } catch {
                errorMessage = MitoriError.map(error).localizedDescription
            }
            isSubmitting = false
        }
    }
}
