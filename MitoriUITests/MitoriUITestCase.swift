//
//  MitoriUITestCase.swift
//  Mitori
//
//  Created by @Zach677 on 2026/10/13.
//

import XCTest

/// Launches the app on an offline fixture (`MITORI_UI_FIXTURE`) and helps tests
/// assert accessibility identifiers and values. Identifiers are the contract
/// between the UI and these tests, so a redesign keeps them.
@MainActor
class MitoriUITestCase: XCTestCase {
    /// `"1"` seeds ready@, expired@, and code@example.com; `"empty"` seeds nothing.
    var fixture: String { "1" }
    /// `"dark"` forces Dark Mode; `nil` keeps the system appearance.
    var appearance: String? { nil }
    var app: XCUIApplication!

    let readyRow = "account-row.ready@example.com"
    let expiredRow = "account-row.expired@example.com"
    let codeRow = "account-row.code@example.com"
    let readyMenuItem = "menu.account.ready@example.com"
    let expiredMenuItem = "menu.account.expired@example.com"

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MITORI_UI_FIXTURE"] = fixture
        app.launchEnvironment["MITORI_UI_APPEARANCE"] = appearance
        app.launch()
    }

    override func tearDown() async throws {
        // The accessibility tree is the evidence an agent reads when a query misses.
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "ax-tree-\(name)"
        tree.lifetime = .keepAlways
        add(tree)
        app.terminate()
    }

    func openStatusMenu() {
        let statusItem = element("menu.status-item")
        // Just after a VM starts, the status item can exist above the screen before the menu bar shows.
        XCTAssertTrue(waitUntil(timeout: 10) { statusItem.exists && statusItem.isHittable }, "status item is not hittable")
        statusItem.click()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func require(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = element(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) missing")
        return element
    }

    func value(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    func waitUntil(_ element: XCUIElement, valueContains text: String, timeout: TimeInterval = 5) -> Bool {
        waitUntil(timeout: timeout) { element.exists && self.value(of: element).contains(text) }
    }

    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    func type(_ text: String, into identifier: String) {
        let field = require(identifier)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + text)
    }

    /// The visible menu or window that contains `identifier`.
    func container(of identifier: String) -> XCUIElement {
        let menu = app.menus.containing(.any, identifier: identifier).firstMatch
        if menu.exists, !menu.frame.isEmpty { return menu }
        return app.windows.containing(.any, identifier: identifier).firstMatch
    }

    /// Saves a named screenshot of one screen state for the UI catalog
    /// (`scripts/export-ui-screens.sh` copies them to `.artifacts/ui-screens/`).
    func captureScreen(_ screen: String, containing identifier: String) {
        captureScreen(screen, of: container(of: identifier))
    }

    func captureScreen(_ screen: String, of target: XCUIElement) {
        let screenshot = target.exists ? target.screenshot() : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "screen-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
