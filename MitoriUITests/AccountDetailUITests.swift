import XCTest

final class AccountDetailUITests: MitoriUITestCase {
    func testDetailShowsBalanceAndInfo() throws {
        openDetail(readyRow)

        let balance = require("account-detail.balance")
        XCTAssertTrue(value(of: balance).contains("12.34"), value(of: balance))
        XCTAssertTrue(element("account-detail.copy.Apple ID").exists)
        XCTAssertEqual(value(of: require("account-detail.probe-bundle-id")), "com.example.probe")
        captureScreen("account-detail", containing: "account-detail.balance")
    }

    func testProbeSearchFillsBundleIDAndSaveRefreshes() throws {
        openDetail(readyRow)

        type("notes", into: "account-detail.probe-search")
        require("account-detail.probe-search-button").click()
        let result = require("account-detail.probe-result.com.example.notes")
        captureScreen("account-detail-search", containing: "account-detail.probe-search")
        result.click()
        let bundleID = require("account-detail.probe-bundle-id")
        XCTAssertEqual(value(of: bundleID), "com.example.notes")

        require("account-detail.save-probe").click()

        // A changed probe closes the window and refreshes the account.
        XCTAssertTrue(waitUntil(require(readyRow, timeout: 10), valueContains: "42.00"))
        XCTAssertFalse(element("account-detail.balance").exists)
    }

    func testClearingProbeSavesAnEmptyProbe() throws {
        openDetail(readyRow)

        type("", into: "account-detail.probe-bundle-id")
        require("account-detail.save-probe").click()
        XCTAssertTrue(waitUntil { !self.element("account-detail.balance").exists }, "a changed probe closes the window")

        require(readyRow, timeout: 10).click()
        XCTAssertEqual(value(of: require("account-detail.probe-bundle-id")), "")
    }

    func testReauthenticationRejectsWrongCodeAndClearsIssue() throws {
        openMenu()
        element("\(expiredRow).refresh").click()
        XCTAssertTrue(waitUntil(require(expiredRow), valueContains: "Session expired"))
        require(expiredRow).click()

        type("000000", into: "account-detail.code")
        require("account-detail.reauthenticate").click()
        let error = require("account-detail.error")
        XCTAssertTrue(waitUntil(error, valueContains: "invalid"), value(of: error))
        captureScreen("account-detail-error", containing: "account-detail.error")

        type("123456", into: "account-detail.code")
        require("account-detail.reauthenticate").click()
        XCTAssertTrue(waitUntil { !self.element("account-detail.error").exists })

        app.typeKey("w", modifierFlags: .command)
        openMenu()
        XCTAssertTrue(waitUntil { !self.value(of: self.require(self.expiredRow)).contains("Session expired") })
    }

    func testDeleteAccountRemovesRow() throws {
        openDetail(readyRow)

        require("account-detail.delete").click()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "delete confirmation missing")
        captureScreen("account-delete-confirm", of: app.dialogs.firstMatch)
        confirm.click()

        XCTAssertTrue(require(expiredRow, timeout: 10).exists)
        XCTAssertFalse(element(readyRow).exists)
    }

    private func openDetail(_ row: String) {
        openMenu()
        require(row).click()
        XCTAssertTrue(require("account-detail.balance").exists)
    }
}
