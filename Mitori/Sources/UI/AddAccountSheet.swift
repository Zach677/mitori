import Observation
import SwiftUI

struct AddAccountSheet: View {
    let model: MitoriModel
    let onClose: () -> Void

    @State private var flow = AddAccountFlowModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case verificationCode
        case probeBundleID
    }

    var body: some View {
        @Bindable var flow = flow

        VStack(spacing: 0) {
            sheetHeader
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 20) {
                credentialsSection

                if flow.requiresVerificationCode {
                    twoFactorSection
                }

                probeSection

                if let errorMessage = flow.errorMessage {
                    errorBanner(errorMessage, recoveryLink: flow.recoveryLink)
                }

                loginButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .task {
            if focusedField == nil {
                focusedField = .email
            }
        }
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)

                Text("Add Apple Account")
                    .font(.system(size: 16, weight: .semibold))
            }

            Text("Sign in with your Apple ID. If two-factor authentication is enabled, a code field will appear after the first attempt.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Apple ID")

            VStack(spacing: 8) {
                TextField("Email", text: Bindable(flow).email)
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: Bindable(flow).password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        if flow.requiresVerificationCode {
                            focusedField = .verificationCode
                        } else {
                            submit()
                        }
                    }
            }
        }
    }

    private var twoFactorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Two-Factor Authentication")

            Text(flow.twoFactorMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Verification Code", text: Bindable(flow).verificationCode)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .verificationCode)
                .onSubmit { submit() }
        }
    }

    private var probeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                sectionLabel("Balance Probe")

                Text("Optional")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.3), in: Capsule())
            }

            TextField("Owned app bundle ID", text: Bindable(flow).probeBundleID)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .probeBundleID)

            Text("Apple's balance API requires a bundle ID from an app this account owns. You can add it later.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorBanner(
        _ message: String,
        recoveryLink: AddAccountFlowModel.RecoveryLink?
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                if let recoveryLink {
                    Link(recoveryLink.title, destination: recoveryLink.url)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loginButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if flow.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(loginButtonTitle)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!flow.canSubmit)
    }

    private var loginButtonTitle: String {
        return flow.requiresVerificationCode ? "Verify & Login" : "Login"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func submit() {
        guard flow.canSubmit else { return }

        flow.beginSubmission()

        Task { @MainActor in
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
                if flow.requiresVerificationCode {
                    focusedField = .verificationCode
                }
            }
            flow.finishSubmission()
        }
    }
}
