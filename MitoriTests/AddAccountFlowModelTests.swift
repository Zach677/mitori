import Foundation
import Testing

@testable import Mitori

@MainActor
struct AddAccountFlowModelTests {
    @Test
    func requiresEmailAndPasswordBeforeLogin() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")

        #expect(flow.canSubmit == false)

        flow.email = "demo@example.com"
        #expect(flow.canSubmit == false)

        flow.password = "secret"
        #expect(flow.canSubmit == true)
    }

    @Test
    func revealingTwoFactorRequiresCodeBeforeRetry() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")
        flow.email = "demo@example.com"
        flow.password = "secret"

        flow.handleFailure(StoreAuthError.codeRequired)

        #expect(flow.requiresVerificationCode == true)
        #expect(flow.canSubmit == false)
        #expect(flow.recoveryLink?.url.absoluteString == "https://account.apple.com")

        flow.verificationCode = "123456"
        #expect(flow.canSubmit == true)
    }

    @Test
    func invalidTwoFactorCodeKeepsFieldVisible() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")
        flow.email = "demo@example.com"
        flow.password = "secret"

        flow.handleFailure(StoreAuthError.invalid2FACode)

        #expect(flow.requiresVerificationCode == true)
        #expect(flow.errorMessage == MitoriError.invalidTwoFactorCode.localizedDescription)
    }

    @Test
    func invalidCredentialsShowAnOptionalCodeField() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")
        flow.email = "demo@example.com"
        flow.password = "secret"

        flow.handleFailure(StoreAuthError.invalidCredentials)

        #expect(flow.showsVerificationCode == true)
        #expect(flow.requiresVerificationCode == false)
        #expect(flow.errorMessage == MitoriError.invalidCredentials.localizedDescription)
        // The password can be the wrong part, so a retry without a code stays possible.
        #expect(flow.canSubmit == true)
    }

    @Test
    func keepsDeviceIdentifierAcrossTwoFactorRetry() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")
        flow.email = "demo@example.com"
        flow.password = "secret"

        flow.handleFailure(MitoriError.twoFactorCodeRequired)
        flow.verificationCode = "123456"

        #expect(flow.deviceIdentifier == "ABCDEF123456")
        #expect(flow.canSubmit == true)
    }

    @Test
    func beginSubmissionClearsErrorAndLocksButton() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")
        flow.email = "demo@example.com"
        flow.password = "secret"
        flow.errorMessage = "Old error"

        flow.beginSubmission()

        #expect(flow.isSubmitting == true)
        #expect(flow.errorMessage == nil)
        #expect(flow.canSubmit == false)

        flow.finishSubmission()
        #expect(flow.canSubmit == true)
    }

    @Test
    func changingEmailResetsTwoFactorState() {
        let flow = AddAccountFlowModel(deviceIdentifier: "ABCDEF123456")
        flow.email = "first@example.com"
        flow.password = "secret"
        flow.handleFailure(StoreAuthError.codeRequired)
        flow.verificationCode = "123456"

        // Case or whitespace changes for the same email keep the 2FA state.
        flow.email = " FIRST@example.com "
        #expect(flow.requiresVerificationCode == true)
        #expect(flow.verificationCode == "123456")

        // Switching to a different email clears the prior account's 2FA prompt.
        flow.email = "second@example.com"
        #expect(flow.requiresVerificationCode == false)
        #expect(flow.offersVerificationCode == false)
        #expect(flow.verificationCode.isEmpty)
        #expect(flow.errorMessage == nil)
        #expect(flow.recoveryLink == nil)
        #expect(flow.canSubmit == true)
    }

    @Test
    func reauthenticateModeSharesTwoFactorAndRecoveryFlowWithoutEmailOrPassword() {
        let flow = AddAccountFlowModel(mode: .reauthenticate, deviceIdentifier: "ABCDEF123456")

        #expect(flow.canSubmit == true)

        flow.handleFailure(StoreAuthError.codeRequired)
        #expect(flow.requiresVerificationCode == true)
        #expect(flow.recoveryLink?.url.absoluteString == "https://account.apple.com")
        #expect(flow.canSubmit == false)

        flow.verificationCode = "123456"
        #expect(flow.canSubmit == true)

        flow.resetAfterSuccess()
        #expect(flow.requiresVerificationCode == false)
        #expect(flow.verificationCode.isEmpty)
        #expect(flow.recoveryLink == nil)
        #expect(flow.errorMessage == nil)
    }
}
