import XCTest

final class MenuPanelUITests: MitoriUITestCase {
    func testMenuListsFixtureAccountsWithBalance() throws {
        openMenu()

        let ready = require(readyRow)
        XCTAssertTrue(value(of: ready).contains("12.34"), value(of: ready))
        XCTAssertTrue(element(expiredRow).exists)
        XCTAssertTrue(value(of: require("menu.summary")).contains("2 accounts"))
        captureScreen("menu-accounts", containing: readyRow)
    }

    func testManualRefreshShowsNewBalance() throws {
        openMenu()
        let ready = require(readyRow)

        element("\(readyRow).refresh").click()

        XCTAssertTrue(waitUntil(ready, valueContains: "42.00"), value(of: ready))
        let banner = element("menu-banner")
        XCTAssertFalse(banner.exists && !value(of: banner).isEmpty, "a success must not show a banner")
    }

    func testFailedRefreshShowsOwnedFailureState() throws {
        openMenu()
        let expired = require(expiredRow)
        XCTAssertFalse(value(of: expired).contains("Session expired"))

        element("\(expiredRow).refresh").click()

        XCTAssertTrue(waitUntil(expired, valueContains: "Session expired"), value(of: expired))
        let banner = require("menu-banner")
        XCTAssertTrue(value(of: banner).contains("Session expired"), value(of: banner))
        // The other account keeps its balance and shows no failure (I-10).
        XCTAssertFalse(value(of: element(readyRow)).contains("expired"))
        captureScreen("menu-failure", containing: expiredRow)
    }

    func testRefreshAllUpdatesEveryAccount() throws {
        openMenu()
        let ready = require(readyRow)

        element("menu.refresh-all").click()

        XCTAssertTrue(waitUntil(ready, valueContains: "42.00"), value(of: ready))
        XCTAssertTrue(waitUntil(element(expiredRow), valueContains: "Session expired"))
    }

    func testMoreMenuOpensSettings() throws {
        openMenu()
        require("menu.more").click()
        require("menu.settings").click()

        XCTAssertTrue(require("settings.auto-refresh").exists)
    }

    func testMoreMenuOpensAboutPanel() throws {
        openMenu()
        require("menu.more").click()
        require("menu.about").click()

        let version = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Version'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5), "About panel did not show a version")
        captureScreen("about", of: app.windows.containing(NSPredicate(format: "value BEGINSWITH 'Version'")).firstMatch)
    }
}

final class EmptyMenuUITests: MitoriUITestCase {
    override var fixture: String { "empty" }

    func testEmptyStateOffersAddAccount() throws {
        openMenu()

        XCTAssertTrue(require("menu.empty-state").exists)
        XCTAssertFalse(element("menu.summary").isHittable)
        captureScreen("menu-empty", containing: "menu.empty-state")

        require("menu.empty-add-account").click()
        XCTAssertTrue(require("add-account.email").exists)
    }
}
