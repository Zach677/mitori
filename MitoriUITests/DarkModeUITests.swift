//
//  DarkModeUITests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/24.
//

import XCTest

/// Captures the main screens in Dark Mode for the UI catalog.
final class DarkModeUITests: MitoriUITestCase {
    override var appearance: String? { "dark" }

    func testMainWindowAndSettingsInDarkMode() throws {
        require(readyRow, timeout: 10).click()
        XCTAssertTrue(require("account-detail.balance").exists)
        captureScreen("dark-main-accounts", containing: "account-detail.balance")

        require(codeRow).click()
        XCTAssertTrue(require("account-detail.issue").exists)
        captureScreen("dark-main-code-needed", containing: "account-detail.issue")

        openStatusMenu()
        captureScreen("dark-status-menu", containing: readyMenuItem)
        require("menu.settings").click()
        XCTAssertTrue(require("settings.auto-refresh").exists)
        captureScreen("dark-settings", containing: "settings.auto-refresh")
    }
}
