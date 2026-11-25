//
//  MainWindowViewTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/08/02.
//

import AppKit
import Foundation
import Testing

@testable import Mitori

@MainActor
struct MainWindowViewTests {
    @Test
    func sidebarPopulatesRowsAndDetailShowsAccountIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            probeAppName: "Pages",
            lastIssue: MitoriError.sessionExpired.refreshIssue(at: Date())
        )
        _ = try await accountStore.upsert(meta)

        let suiteName = "test.main.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RefreshSettingsStore(defaults: defaults)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub(),
            settings: settings
        )
        await model.loadAccountsIfNeeded()

        let detail = AccountDetailViewController(
            model: model,
            settings: settings,
            onRefreshRequested: { _ in }
        )
        detail.loadView()
        detail.setAccountID(meta.id)

        let issueView = try #require(findView(withIdentifier: "account-detail.issue", in: detail.view))
        #expect(!issueView.isHiddenOrHasHiddenAncestor)
        let probeLabel = try #require(findTextField(withIdentifier: "account-detail.probe-value", in: detail.view))
        #expect(probeLabel.stringValue == "Pages")
    }

    @Test
    func networkIssueWithoutAutoRefreshOffersRefreshActionAndNoRetryCountdown() {
        let account = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            lastIssue: MitoriError.network("offline").refreshIssue(at: Date())
        )

        let manualPresentation = AccountIssuePresentation(account: account, nextAutoRefreshAt: nil)
        #expect(manualPresentation?.action == .refresh)
        #expect(manualPresentation?.metadata.contains("try again") == false)

        let scheduledPresentation = AccountIssuePresentation(
            account: account,
            nextAutoRefreshAt: Date().addingTimeInterval(600)
        )
        #expect(scheduledPresentation?.action == nil)
        #expect(scheduledPresentation?.metadata.contains("try again") == true)
    }

    @Test
    func unknownIssueRemainsVisibleWithRefreshAction() {
        let account = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            lastIssue: MitoriError.unknown("Unexpected server state").refreshIssue(at: Date())
        )

        let presentation = AccountIssuePresentation(account: account, nextAutoRefreshAt: nil)
        #expect(presentation?.sidebarHint == "Needs attention")
        #expect(presentation?.message == "Unexpected server state")
        #expect(presentation?.action == .refresh)
    }

    private func findView(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = findView(withIdentifier: identifier, in: subview) { return match }
        }
        return nil
    }

    private func findTextField(withIdentifier identifier: String, in view: NSView) -> NSTextField? {
        findView(withIdentifier: identifier, in: view) as? NSTextField
    }
}

struct TimestampTextTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test
    func freshnessIsRelativeWithinADay() {
        #expect(now.addingTimeInterval(-20).freshnessText(relativeTo: now) == "just now")
        #expect(now.addingTimeInterval(-240).freshnessText(relativeTo: now).contains("4"))
        #expect(now.addingTimeInterval(-25 * 60 * 60).freshnessText(relativeTo: now)
            == now.addingTimeInterval(-25 * 60 * 60).shortTimestamp(relativeTo: now))
    }

    @Test
    func shortTimestampShowsYearOnlyForAnotherYear() {
        let year = String(Calendar.current.component(.year, from: now))
        #expect(!now.addingTimeInterval(-60 * 60).shortTimestamp(relativeTo: now).contains(year))
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        #expect(lastYear.shortTimestamp(relativeTo: now).contains(String(Calendar.current.component(.year, from: lastYear))))
    }
}
