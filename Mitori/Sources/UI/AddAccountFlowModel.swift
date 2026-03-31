import Foundation
import Observation

@MainActor
@Observable
final class AddAccountFlowModel {
    var email = ""
    var password = ""
    var verificationCode = ""
    var probeBundleID = ""
    var errorMessage: String?
    var isSubmitting = false
    var requiresVerificationCode = false

    var canSubmit: Bool {
        let hasCredentials = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        let hasVerificationCode = !requiresVerificationCode ||
            !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !isSubmitting && hasCredentials && hasVerificationCode
    }

    var twoFactorMessage: String {
        if requiresVerificationCode {
            return "Apple wants a 2FA code. Paste it here, then tap Login again."
        }

        return "No code field yet. If Apple asks for 2FA, it shows up after the first login attempt."
    }

    func beginSubmission() {
        isSubmitting = true
        errorMessage = nil
    }

    func finishSubmission() {
        isSubmitting = false
    }

    func handleFailure(_ error: Error) {
        let mappedError = MitoriError.map(error)

        switch mappedError {
        case .twoFactorCodeRequired:
            requiresVerificationCode = true
            errorMessage = "This Apple ID needs a 2FA code. Enter it below, then tap Login again."
        case .invalidTwoFactorCode:
            requiresVerificationCode = true
            errorMessage = mappedError.localizedDescription
        default:
            errorMessage = mappedError.localizedDescription
        }
    }
}
