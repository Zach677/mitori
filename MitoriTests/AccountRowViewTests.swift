import AppKit
import Testing

@testable import Mitori

struct AccountRowViewTests {
    @Test
    @MainActor
    func hitTestingWorksWhenRowHasNonzeroOrigin() throws {
        let account = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let row = AccountRowView(
            account: account,
            presentation: AccountPresentation(
                account: account,
                accountIndex: 0,
                hidesPersonalInformation: false
            ),
            refreshState: .idle,
            onOpen: {},
            onRefresh: {}
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        row.frame = NSRect(x: 0, y: 70, width: 360, height: 56)
        container.addSubview(row)
        row.layoutSubtreeIfNeeded()

        let pointInContainer = NSPoint(x: row.frame.midX, y: row.frame.midY)
        let actionButton = try #require(
            row.subviews.first?.subviews.compactMap { $0 as? NSButton }.first
        )
        let actionPointInContainer = container.convert(
            NSPoint(x: actionButton.bounds.midX, y: actionButton.bounds.midY),
            from: actionButton
        )

        #expect(container.hitTest(pointInContainer) === row)
        #expect(container.hitTest(actionPointInContainer) === actionButton)
    }
}
