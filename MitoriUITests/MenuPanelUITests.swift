import XCTest

/// Drives the real app against the offline `MITORI_UI_FIXTURE` accounts.
/// Assertions read accessibility identifiers and values, so each test is a
/// machine-checked PASS/FAIL; screenshots are kept in the result bundle.
final class MenuPanelUITests: XCTestCase {
    private let readyRow = "account-row.ready@example.com"
    private let expiredRow = "account-row.expired@example.com"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MITORI_UI_FIXTURE"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        attachScreenshot(named: "final-\(name)")
        // The accessibility tree is the evidence an agent reads when a query misses.
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "ax-tree-\(name)"
        tree.lifetime = .keepAlways
        add(tree)
        app.terminate()
    }

    func testMenuListsFixtureAccountsWithBalance() throws {
        openMenu()

        let ready = element(readyRow)
        XCTAssertTrue(ready.waitForExistence(timeout: 5), "ready row missing")
        XCTAssertTrue(value(of: ready).contains("12.34"), value(of: ready))
        XCTAssertTrue(element(expiredRow).exists)
    }

    func testManualRefreshShowsNewBalance() throws {
        openMenu()
        let ready = element(readyRow)
        XCTAssertTrue(ready.waitForExistence(timeout: 5), "ready row missing")

        element("\(readyRow).refresh").click()

        XCTAssertTrue(waitUntil(ready, valueContains: "42.00"), value(of: ready))
        XCTAssertFalse(element("menu-banner").exists && !value(of: element("menu-banner")).isEmpty)
    }

    func testFailedRefreshShowsOwnedFailureState() throws {
        openMenu()
        let expired = element(expiredRow)
        XCTAssertTrue(expired.waitForExistence(timeout: 5), "expired row missing")

        element("\(expiredRow).refresh").click()

        XCTAssertTrue(waitUntil(expired, valueContains: "Session expired"), value(of: expired))
        let banner = element("menu-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "banner missing")
        XCTAssertTrue(value(of: banner).contains("Session expired"), value(of: banner))
        // The other account keeps its balance and shows no failure (I-10).
        XCTAssertFalse(value(of: element(readyRow)).contains("expired"))
    }

    private func openMenu() {
        let statusItem = element("mitori-status-item")
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "status item did not appear")
        statusItem.click()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func value(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    private func waitUntil(_ element: XCUIElement, valueContains text: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, value(of: element).contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
