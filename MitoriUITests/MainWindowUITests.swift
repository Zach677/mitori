//
//  MainWindowUITests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/10/13.
//

import XCTest

final class MainWindowUITests: MitoriUITestCase {
    func testMainWindowListsFixtureAccountsWithBalance() throws {
        let ready = require(readyRow, timeout: 10)
        XCTAssertTrue(value(of: ready).contains("12.34"), value(of: ready))
        XCTAssertTrue(element(expiredRow).exists)
        captureScreen("main-accounts", containing: readyRow)
    }

    func testStatusMenuListsAccountsAndOpensSettings() throws {
        openStatusMenu()

        XCTAssertTrue(require(readyMenuItem).exists)
        XCTAssertTrue(require(expiredMenuItem).exists)
        XCTAssertTrue(require("menu.add-account").exists)
        XCTAssertFalse(element("menu.hide-personal-info").exists)
        captureScreen("status-menu", containing: readyMenuItem)

        require("menu.settings").click()
        XCTAssertTrue(require("settings.auto-refresh").exists)
    }

    func testManualRefreshShowsNewBalance() throws {
        let ready = require(readyRow, timeout: 10)
        ready.click()
        require("main.refresh").click()

        let updated = require("account-detail.updated")
        XCTAssertTrue(waitUntil(updated, valueContains: "Refreshing"), value(of: updated))
        captureScreen("main-refreshing", containing: "account-detail.balance")

        XCTAssertTrue(waitUntil(ready, valueContains: "42.00"), value(of: ready))
        XCTAssertFalse(element("account-detail.issue").exists && element("account-detail.issue").isHittable)
    }

    func testFailedRefreshShowsOwnedFailureState() throws {
        let expired = require(expiredRow, timeout: 10)
        expired.click()
        XCTAssertFalse(value(of: expired).contains("Session expired"))

        require("main.refresh").click()

        XCTAssertTrue(waitUntil(expired, valueContains: "Session expired"), value(of: expired))
        let issue = require("account-detail.issue")
        XCTAssertTrue(waitUntil(issue, valueContains: "Session expired"), value(of: issue))
        // The other account keeps its balance and shows no failure (I-10).
        XCTAssertFalse(value(of: element(readyRow)).contains("expired"))
        captureScreen("main-failure", containing: "account-detail.issue")

        openStatusMenu()
        XCTAssertTrue(require(expiredMenuItem).exists)
        captureScreen("status-menu-issues", containing: expiredMenuItem)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testRefreshAllUpdatesEveryAccount() throws {
        let ready = require(readyRow, timeout: 10)
        openStatusMenu()
        require("menu.refresh-all").click()

        // Each fixture refresh takes 2 s.
        XCTAssertTrue(waitUntil(ready, valueContains: "42.00", timeout: 15), value(of: ready))
        XCTAssertTrue(waitUntil(element(expiredRow), valueContains: "Session expired", timeout: 15))
    }

    func testAppMenuOpensAboutPanel() throws {
        _ = require(readyRow, timeout: 10)
        app.menuBars.menuBarItems["Mitori"].click()
        require("menu.about").click()

        let version = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Version'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5), "About panel did not show a version")
        captureScreen("about", of: app.windows.containing(NSPredicate(format: "value BEGINSWITH 'Version'")).firstMatch)
    }
}

final class EmptyMenuUITests: MitoriUITestCase {
    override var fixture: String { "empty" }

    func testEmptyStateOffersAddAccount() throws {
        XCTAssertTrue(require("main.empty-state", timeout: 10).exists)
        captureScreen("main-empty", containing: "main.empty-state")

        require("menu.empty-add-account").click()
        XCTAssertTrue(require("add-account.email").exists)
    }
}
