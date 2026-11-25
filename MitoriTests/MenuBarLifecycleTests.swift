//
//  MenuBarLifecycleTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import AppKit
import Foundation
import Testing

@testable import Mitori

@MainActor
struct DockIconPolicyControllerTests {
    @MainActor
    private final class WindowState {
        var isVisible: Bool
        var applied: [NSApplication.ActivationPolicy] = []

        init(isVisible: Bool) {
            self.isVisible = isVisible
        }
    }

    @Test
    func hidesInAccessoryModeWhenNoWindowIsVisibleAndPreferenceIsOn() {
        let state = WindowState(isVisible: true)
        let controller = DockIconPolicyController(
            hidesWhenClosed: { true },
            hasVisibleWindow: { state.isVisible },
            applyPolicy: { state.applied.append($0) }
        )

        controller.update()
        #expect(controller.currentPolicy == .regular)
        #expect(state.applied == [.regular])

        state.isVisible = false
        controller.update()
        #expect(controller.currentPolicy == .accessory)
        #expect(state.applied == [.regular, .accessory])
    }

    @Test
    func staysRegularWhenHidePreferenceIsOff() {
        let state = WindowState(isVisible: false)
        let controller = DockIconPolicyController(
            hidesWhenClosed: { false },
            hasVisibleWindow: { false },
            applyPolicy: { state.applied.append($0) }
        )

        controller.update()
        #expect(controller.currentPolicy == .regular)
        #expect(state.applied == [.regular])
    }

    @Test
    func ensureRegularSynchronizesPolicySoClosingReturnsToAccessory() {
        let state = WindowState(isVisible: false)
        let controller = DockIconPolicyController(
            hidesWhenClosed: { true },
            hasVisibleWindow: { state.isVisible },
            applyPolicy: { state.applied.append($0) }
        )

        controller.ensureRegular()
        #expect(controller.currentPolicy == .regular)
        #expect(state.applied == [.regular])

        // Even if no regular window stays visible, update() transitions back to .accessory.
        state.isVisible = false
        controller.update()
        #expect(controller.currentPolicy == .accessory)
        #expect(state.applied == [.regular, .accessory])
    }

    @Test
    func hideDockIconSettingDefaultsToTrue() throws {
        let suiteName = "test.dock.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RefreshSettingsStore(defaults: defaults)

        #expect(settings.hidesDockIconWhenClosed == true)
        settings.hidesDockIconWhenClosed = false
        #expect(settings.hidesDockIconWhenClosed == false)
    }
}

@MainActor
struct StatusMenuBuilderTests {
    @Test
    func emptyStateShowsNoAccountsAndAddAccount() {
        let menu = NSMenu()
        StatusMenuBuilder.populate(
            menu,
            accounts: [],
            loadError: nil,
            isRefreshingAll: false,
            hidesPersonalInformation: false,
            refreshStateFor: { _ in .idle },
            nextAutoRefreshFor: { _ in nil },
            actions: makeActions()
        )

        let ids = menu.items.compactMap { $0.identifier?.rawValue }
        #expect(ids.contains("menu.empty-state"))
        #expect(ids.contains("menu.add-account"))
        #expect(!ids.contains("menu.refresh-all"))
        #expect(ids.contains("menu.settings"))
        #expect(ids.contains("menu.quit"))
    }

    @Test
    func loadErrorStateShowsLoadErrorInsteadOfEmptyState() {
        let menu = NSMenu()
        StatusMenuBuilder.populate(
            menu,
            accounts: [],
            loadError: "corrupt json",
            isRefreshingAll: false,
            hidesPersonalInformation: false,
            refreshStateFor: { _ in .idle },
            nextAutoRefreshFor: { _ in nil },
            actions: makeActions()
        )

        let ids = menu.items.compactMap { $0.identifier?.rawValue }
        #expect(ids.contains("menu.load-error"))
        #expect(!ids.contains("menu.empty-state"))
    }

    @Test
    func populatedMenuIncludesAccountItemsAndRefreshAll() {
        var meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        meta.balanceSnapshot = BalanceSnapshot(
            displayText: "$12.34",
            numericValue: Decimal(string: "12.34"),
            currencyCode: "USD",
            fetchedAt: Date(),
            source: .probe,
            rawFieldPath: "creditDisplay"
        )
        let menu = NSMenu()
        StatusMenuBuilder.populate(
            menu,
            accounts: [meta],
            loadError: nil,
            isRefreshingAll: false,
            hidesPersonalInformation: false,
            refreshStateFor: { _ in .idle },
            nextAutoRefreshFor: { _ in nil },
            actions: makeActions()
        )

        let accountItem = menu.items.first { $0.identifier?.rawValue == "menu.account.\(meta.id)" }
        #expect(accountItem != nil)
        #expect(accountItem?.badge?.stringValue == "$12.34")
        let ids = menu.items.compactMap { $0.identifier?.rawValue }
        #expect(ids.contains("menu.refresh-all"))
        #expect(ids.contains("menu.add-account"))
        #expect(!ids.contains("menu.hide-personal-info"))
        #expect(!ids.contains("menu.about"))
    }

    private func makeActions() -> StatusMenuBuilder.Actions {
        let sel = #selector(NSObject.description)
        return StatusMenuBuilder.Actions(
            target: nil,
            openAccount: sel,
            addAccount: sel,
            refreshAll: sel,
            openMainWindow: sel,
            openSettings: sel,
            quit: sel
        )
    }
}

@MainActor
struct WindowPresentationCoordinatorTests {
    @Test
    func firstPresentationShowsWindow() {
        let window = WindowSpy(isVisible: false)
        let coordinator = WindowPresentationCoordinator(window: window)

        coordinator.present()

        #expect(window.showCount == 1)
        #expect(window.focusCount == 0)
    }

    @Test
    func repeatedPresentationFocusesExistingWindow() {
        let window = WindowSpy(isVisible: true)
        let coordinator = WindowPresentationCoordinator(window: window)

        coordinator.present()

        #expect(window.showCount == 0)
        #expect(window.focusCount == 1)
    }
}

@MainActor
private final class WindowSpy: WindowVisibilityManaging {
    var isVisible: Bool
    private(set) var showCount = 0
    private(set) var focusCount = 0

    init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    func show() {
        showCount += 1
        isVisible = true
    }

    func focus() {
        focusCount += 1
    }
}
