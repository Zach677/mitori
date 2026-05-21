import Foundation
import Testing

@testable import Mitori

@MainActor
struct AddAccountFlowModelTests {
    @Test
    func requiresEmailAndPasswordBeforeLogin() {
        let flow = AddAccountFlowModel()

        #expect(flow.canSubmit == false)

        flow.email = "demo@example.com"
        #expect(flow.canSubmit == false)

        flow.password = "secret"
        #expect(flow.canSubmit == true)
    }

    @Test
    func revealingTwoFactorRequiresCodeBeforeRetry() {
        let flow = AddAccountFlowModel()
        flow.email = "demo@example.com"
        flow.password = "secret"

        flow.handleFailure(NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Authentication requires verification code"]
        ))

        #expect(flow.requiresVerificationCode == true)
        #expect(flow.canSubmit == false)
        #expect(flow.recoveryLink?.url.absoluteString == "https://account.apple.com")

        flow.verificationCode = "123456"
        #expect(flow.canSubmit == true)
    }

    @Test
    func invalidTwoFactorCodeKeepsFieldVisible() {
        let flow = AddAccountFlowModel()
        flow.email = "demo@example.com"
        flow.password = "secret"

        flow.handleFailure(NSError(
            domain: "Test",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Invalid or expired 2FA code"]
        ))

        #expect(flow.requiresVerificationCode == true)
        #expect(flow.errorMessage == MitoriError.invalidTwoFactorCode.localizedDescription)
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
        let flow = AddAccountFlowModel()
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
}
