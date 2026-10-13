import XCTest

final class SettingsUITests: MitoriUITestCase {
    func testSettingsShowsEveryControl() throws {
        openSettings()

        // Open at login changes a real login item, so tests only check that it exists.
        for identifier in [
            "settings.open-at-login", "settings.hide-personal-information",
            "settings.auto-refresh", "settings.interval",
            "settings.privacy-policy", "settings.licenses",
        ] {
            XCTAssertTrue(require(identifier).exists)
        }
        XCTAssertEqual(require("settings.hide-personal-information").label, "Hide personal information")
        captureScreen("settings", containing: "settings.auto-refresh")
    }

    func testAutoRefreshEnablesInterval() throws {
        openSettings()
        let interval = require("settings.interval")
        XCTAssertFalse(interval.isEnabled)

        require("settings.auto-refresh").click()

        XCTAssertTrue(waitUntil { interval.isEnabled })
    }

    func testHidePersonalInformationMasksAccounts() throws {
        openSettings()
        require("settings.hide-personal-information").click()

        openMenu()
        let ready = require(readyRow)
        XCTAssertFalse(ready.label.contains("Ready"), ready.label)
        XCTAssertFalse(app.staticTexts["ready@example.com"].exists)
        captureScreen("menu-hidden-personal-information", containing: readyRow)
    }

    func testLicensesOpenDocument() throws {
        openSettings()
        require("settings.licenses").click()

        let document = require("document.content")
        XCTAssertTrue(value(of: document).contains("MIT") || document.label.contains("License"))
        captureScreen("licenses", containing: "document.content")
    }

    private func openSettings() {
        openMenu()
        require("menu.more").click()
        require("menu.settings").click()
        XCTAssertTrue(require("settings.auto-refresh").exists)
    }
}
