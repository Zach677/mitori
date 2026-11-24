//
//  AddAccountFlowModel.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/31.
//

import Foundation

@MainActor
final class AddAccountFlowModel {
    enum Mode: Equatable {
        case addAccount
        case reauthenticate
    }

    struct RecoveryLink: Equatable {
        var title: String
        var url: URL
    }

    let mode: Mode
    var email = "" {
        didSet {
            guard mode == .addAccount else { return }
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let twoFactorEmail, normalized != twoFactorEmail {
                resetTwoFactorState()
            }
        }
    }
    var password = ""
    var verificationCode = ""
    var errorMessage: String?
    var recoveryLink: RecoveryLink?
    var isSubmitting = false
    var requiresVerificationCode = false
    /// Apple gives the same answer for a wrong password and for a missing 2FA code (#2),
    /// so the code field shows but stays optional.
    var offersVerificationCode = false
    var showsVerificationCode: Bool { requiresVerificationCode || offersVerificationCode }
    let deviceIdentifier: String
    private var twoFactorEmail: String?

    private static let appleAccountRecoveryLink = RecoveryLink(
        title: "Open account.apple.com",
        url: URL(string: "https://account.apple.com")!
    )

    init(
        mode: Mode = .addAccount,
        deviceIdentifier: String = DeviceIdentifierProvider.make()
    ) {
        self.mode = mode
        self.deviceIdentifier = deviceIdentifier
    }

    var canSubmit: Bool {
        let hasVerificationCode = !requiresVerificationCode ||
            !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch mode {
        case .addAccount:
            let hasCredentials = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
            return !isSubmitting && hasCredentials && hasVerificationCode
        case .reauthenticate:
            return !isSubmitting && hasVerificationCode
        }
    }

    var twoFactorMessage: String {
        if requiresVerificationCode {
            return "Apple requires a 2FA code. Enter it here, then sign in again."
        }
        if offersVerificationCode {
            return "If your devices showed a verification code, enter it here, then sign in again."
        }

        return "If Apple asks for 2FA, this field appears after the first sign-in attempt."
    }

    func beginSubmission() {
        isSubmitting = true
        errorMessage = nil
        recoveryLink = nil
    }

    func finishSubmission() {
        isSubmitting = false
    }

    func resetAfterSuccess() {
        resetTwoFactorState()
        isSubmitting = false
    }

    func handleFailure(_ error: Error) {
        let mappedError = MitoriError.map(error)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch mappedError {
        case .twoFactorCodeRequired:
            twoFactorEmail = normalizedEmail
            requiresVerificationCode = true
            errorMessage = "This Apple ID needs a 2FA code. Enter it and sign in again. If no prompt appeared, open Apple Account to trigger it."
            recoveryLink = Self.appleAccountRecoveryLink
        case .invalidTwoFactorCode:
            twoFactorEmail = normalizedEmail
            requiresVerificationCode = true
            errorMessage = mappedError.localizedDescription
        case .invalidCredentials:
            twoFactorEmail = normalizedEmail
            offersVerificationCode = true
            errorMessage = mappedError.localizedDescription
        default:
            errorMessage = mappedError.localizedDescription
        }
    }

    private func resetTwoFactorState() {
        twoFactorEmail = nil
        requiresVerificationCode = false
        offersVerificationCode = false
        verificationCode = ""
        errorMessage = nil
        recoveryLink = nil
    }
}
