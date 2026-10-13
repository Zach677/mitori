import XCTest

final class AddAccountUITests: MitoriUITestCase {
    func testTwoFactorFlowAddsAccount() throws {
        openMenu()
        require("menu.add-account").click()
        let submit = require("add-account.submit")
        XCTAssertFalse(submit.isEnabled, "Login must wait for email and password")
        captureScreen("add-account", containing: "add-account.email")

        type("new@example.com", into: "add-account.email")
        type("password", into: "add-account.password")
        XCTAssertTrue(submit.isEnabled)
        submit.click()

        XCTAssertTrue(require("add-account.code").exists)
        XCTAssertTrue(require("add-account.recovery").exists)
        captureScreen("add-account-2fa", containing: "add-account.code")

        type("000000", into: "add-account.code")
        submit.click()
        let error = require("add-account.error")
        XCTAssertTrue(waitUntil(error, valueContains: "invalid"), value(of: error))
        captureScreen("add-account-invalid-code", containing: "add-account.error")

        type("123456", into: "add-account.code")
        submit.click()

        let newRow = require("account-row.new@example.com", timeout: 10)
        XCTAssertTrue(value(of: newRow).contains("7.50"), value(of: newRow))
        XCTAssertFalse(element("add-account.email").exists, "Add Account window must close")
    }

    func testCancelClosesWindow() throws {
        openMenu()
        require("menu.add-account").click()

        require("add-account.cancel").click()

        XCTAssertTrue(waitUntil { !self.element("add-account.email").exists })
    }
}
