//
//  AccountDetailUITests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/10/13.
//

import XCTest

final class AccountDetailUITests: MitoriUITestCase {
    func testDetailShowsBalanceAndInfo() throws {
        selectAccount(readyRow)

        let balance = require("account-detail.balance")
        XCTAssertTrue(value(of: balance).contains("12.34"), value(of: balance))
        XCTAssertTrue(element("account-detail.copy.Apple ID").exists)
        XCTAssertEqual(value(of: require("account-detail.probe-value")), "Fixture Pages")
        XCTAssertEqual(require("account-detail.choose-probe").title, "Change…")
        // At the default window size the whole detail fits, so no scroller appears.
        let window = container(of: "account-detail.balance")
        XCTAssertLessThanOrEqual(require("account-detail.delete").frame.maxY, window.frame.maxY - 8)
        captureScreen("account-detail", containing: "account-detail.balance")
    }

    func testProbeSearchFillsBundleIDAndSaveRefreshes() throws {
        selectAccount(readyRow)
        require("account-detail.choose-probe").click()

        type("notes", into: "account-detail.probe-search")
        app.typeKey(.return, modifierFlags: [])
        let result = require("account-detail.probe-result.com.example.notes")
        XCTAssertFalse(element("account-detail.probe-bundle-id").exists, "manual entry starts collapsed")
        captureScreen("choose-probe-search", containing: "account-detail.probe-search")
        result.click()
        require("account-detail.probe-manual").click()
        let bundleID = require("account-detail.probe-bundle-id")
        XCTAssertEqual(value(of: bundleID), "com.example.notes")
        captureScreen("choose-probe-manual", containing: "account-detail.probe-bundle-id")

        require("account-detail.save-probe").click()

        XCTAssertTrue(waitUntil(require(readyRow, timeout: 10), valueContains: "42.00"))
        XCTAssertEqual(value(of: require("account-detail.probe-value")), "Fixture Notes")
    }

    func testClearingProbeSavesAnEmptyProbe() throws {
        selectAccount(readyRow)
        require("account-detail.choose-probe").click()

        require("account-detail.clear-probe").click()
        let probeValue = require("account-detail.probe-value")
        XCTAssertTrue(waitUntil(probeValue, valueContains: "None"), value(of: probeValue))
    }

    func testReauthenticationRejectsWrongCodeAndClearsIssue() throws {
        selectAccount(expiredRow)
        require("main.refresh").click()
        XCTAssertTrue(waitUntil(require(expiredRow), valueContains: "Session expired"))

        require("account-detail.issue-action").click()
        XCTAssertTrue(require("account-detail.password").exists)
        require("account-detail.reauthenticate-submit").click()

        // First attempt without code reveals 2FA code input.
        let codeField = require("account-detail.code")
        XCTAssertTrue(codeField.exists)
        type("000000", into: "account-detail.code")
        require("account-detail.reauthenticate-submit").click()

        let error = require("account-detail.error")
        XCTAssertTrue(waitUntil(error, valueContains: "invalid"), value(of: error))
        captureScreen("sign-in-again-error", containing: "account-detail.error")

        type("123456", into: "account-detail.code")
        require("account-detail.reauthenticate-submit").click()

        XCTAssertTrue(waitUntil { !self.element("account-detail.reauthenticate-submit").exists })
        XCTAssertTrue(waitUntil { !self.value(of: self.require(self.expiredRow)).contains("Session expired") })
    }

    func testCodeNeededShowsIssueAndCodeField() throws {
        let code = require(codeRow, timeout: 10)
        XCTAssertTrue(value(of: code).contains("Code needed"), value(of: code))
        code.click()

        let issue = require("account-detail.issue")
        XCTAssertTrue(waitUntil(issue, valueContains: "Verification"), value(of: issue))
        XCTAssertFalse(element("account-detail.reauthenticate").exists, "the issue row already offers sign-in")
        captureScreen("main-code-needed", containing: "account-detail.issue")

        require("account-detail.issue-action").click()
        XCTAssertTrue(require("account-detail.code").exists)
        captureScreen("sign-in-again-code", containing: "account-detail.code")
        require("account-detail.reauth-cancel").click()
        XCTAssertTrue(waitUntil { !self.element("account-detail.code").exists })
    }

    func testRemoveAccountRemovesRow() throws {
        selectAccount(readyRow)

        require("account-detail.delete").click()
        let confirm = app.buttons["Remove"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "remove confirmation missing")
        captureScreen("account-remove-confirm", of: app.sheets.firstMatch)
        confirm.click()

        XCTAssertTrue(require(expiredRow, timeout: 10).exists)
        XCTAssertFalse(element(readyRow).exists)
    }

    private func selectAccount(_ row: String) {
        require(row, timeout: 10).click()
        XCTAssertTrue(require("account-detail.balance").exists)
    }
}
