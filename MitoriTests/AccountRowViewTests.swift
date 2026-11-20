//
//  AccountRowViewTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/08/02.
//

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

    @Test
    @MainActor
    func menuPanelScrollViewStartsAtFirstAccount() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        for index in 0 ..< 12 {
            var account = sampleAccount()
            account.email = String(format: "user%02d@example.com", index)
            account.firstName = "User"
            account.lastName = "\(index)"
            _ = try await accountStore.upsert(StoredAccountMeta(
                account: account,
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            ))
        }

        let suiteName = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RefreshSettingsStore(defaults: defaults)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub(),
            settings: settings
        )
        await model.menuPresented()

        let controller = MenuPanelViewController(
            model: model,
            settings: settings,
            onAddAccount: {},
            onOpenAccount: { _ in },
            onOpenAbout: {},
            onOpenSettings: {},
            onQuit: {}
        )
        controller.loadView()
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = try #require(findSubview(ofType: NSScrollView.self, in: controller.view))
        let documentStack = try #require(scrollView.documentView as? NSStackView)
        let firstRow = try #require(documentStack.arrangedSubviews.first)
        #expect(scrollView.documentVisibleRect.intersects(firstRow.frame))
    }

    @Test
    @MainActor
    func clearingProbeFieldSurvivesReload() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)

        let suiteName = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RefreshSettingsStore(defaults: defaults)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub(),
            settings: settings
        )
        await model.menuPresented()

        let controller = AccountDetailViewController(
            model: model,
            settings: settings,
            accountID: meta.id,
            onClose: {},
            onProbeSaved: { _ in }
        )
        controller.loadView()

        let probeField = try #require(findTextField(withIdentifier: "account-detail.probe-bundle-id", in: controller.view))
        #expect(probeField.stringValue == "com.example.probe")

        probeField.stringValue = ""
        controller.reload()

        #expect(probeField.stringValue.isEmpty)
        let probeFieldAfterReload = try #require(
            findTextField(withIdentifier: "account-detail.probe-bundle-id", in: controller.view)
        )
        #expect(probeFieldAfterReload === probeField)
    }

    @Test
    @MainActor
    func menuPanelReusesRowViewsAcrossReloads() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RefreshSettingsStore(defaults: defaults)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub(),
            settings: settings
        )
        await model.menuPresented()

        let controller = MenuPanelViewController(
            model: model,
            settings: settings,
            onAddAccount: {},
            onOpenAccount: { _ in },
            onOpenAbout: {},
            onOpenSettings: {},
            onQuit: {}
        )
        controller.loadView()

        let scrollView = try #require(findSubview(ofType: NSScrollView.self, in: controller.view))
        let stack = try #require(scrollView.documentView as? NSStackView)
        let initialRow = try #require(stack.arrangedSubviews.first as? AccountRowView)

        controller.reload()

        let reloadedRow = try #require(stack.arrangedSubviews.first as? AccountRowView)
        #expect(reloadedRow === initialRow)
    }

    @MainActor
    private func findSubview<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = findSubview(ofType: type, in: subview) { return match }
        }
        return nil
    }

    @MainActor
    private func findTextField(withIdentifier identifier: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.accessibilityIdentifier() == identifier {
            return field
        }
        for subview in view.subviews {
            if let match = findTextField(withIdentifier: identifier, in: subview) { return match }
        }
        return nil
    }
}
