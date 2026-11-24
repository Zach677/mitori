//
//  StatusMenuBuilder.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/25.
//

import AppKit

@MainActor
enum StatusMenuBuilder {
    struct Actions {
        weak var target: AnyObject?
        var openAccount: Selector
        var addAccount: Selector
        var refreshAll: Selector
        var openMainWindow: Selector
        var openSettings: Selector
        var quit: Selector
    }

    static func populate(
        _ menu: NSMenu,
        accounts: [StoredAccountMeta],
        loadError: String?,
        isRefreshingAll: Bool,
        hidesPersonalInformation: Bool,
        refreshStateFor: (String) -> RefreshState,
        nextAutoRefreshFor: (String) -> Date?,
        actions: Actions
    ) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let headerTitle = isRefreshingAll ? "Refreshing…" : "Store Credit"
        menu.addItem(NSMenuItem.sectionHeader(title: headerTitle))

        if loadError != nil, accounts.isEmpty {
            let errorItem = NSMenuItem(title: "Couldn't Load Accounts", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            errorItem.identifier = NSUserInterfaceItemIdentifier("menu.load-error")
            menu.addItem(errorItem)
        } else if accounts.isEmpty {
            let emptyItem = NSMenuItem(title: "No Accounts", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            emptyItem.identifier = NSUserInterfaceItemIdentifier("menu.empty-state")
            menu.addItem(emptyItem)

            menu.addItem(makeAddAccountItem(actions))
        } else {
            for (index, account) in accounts.enumerated() {
                let presentation = AccountPresentation(
                    account: account,
                    accountIndex: index,
                    hidesPersonalInformation: hidesPersonalInformation
                )
                let issue = AccountIssuePresentation(
                    account: account,
                    nextAutoRefreshAt: nextAutoRefreshFor(account.id)
                )
                let refreshState = refreshStateFor(account.id)
                menu.addItem(makeAccountItem(
                    account: account,
                    presentation: presentation,
                    refreshState: refreshState,
                    issue: issue,
                    target: actions.target,
                    action: actions.openAccount
                ))
            }
        }

        menu.addItem(.separator())

        if !accounts.isEmpty {
            let refreshAllItem = NSMenuItem(title: "Refresh All", action: actions.refreshAll, keyEquivalent: "R")
            refreshAllItem.keyEquivalentModifierMask = [.command, .shift]
            refreshAllItem.target = actions.target
            refreshAllItem.isEnabled = !isRefreshingAll
            refreshAllItem.identifier = NSUserInterfaceItemIdentifier("menu.refresh-all")
            menu.addItem(refreshAllItem)
            menu.addItem(makeAddAccountItem(actions))
            menu.addItem(.separator())
        }

        let openItem = NSMenuItem(title: "Open Mitori", action: actions.openMainWindow, keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = .command
        openItem.target = actions.target
        openItem.identifier = NSUserInterfaceItemIdentifier("menu.open")
        // macOS 26 gives "Settings…" a gear; an image here keeps the section in one aligned column.
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: actions.openSettings, keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = actions.target
        settingsItem.identifier = NSUserInterfaceItemIdentifier("menu.settings")
        if #available(macOS 27.0, *) {
            // macOS 27 hides our image but still shows the automatic gear; hide both so the column stays aligned.
            openItem.preferredImageVisibility = .hidden
            settingsItem.preferredImageVisibility = .hidden
        }
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Mitori", action: actions.quit, keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = actions.target
        quitItem.identifier = NSUserInterfaceItemIdentifier("menu.quit")
        menu.addItem(quitItem)
    }

    private static func makeAddAccountItem(_ actions: Actions) -> NSMenuItem {
        let item = NSMenuItem(title: "Add Account…", action: actions.addAccount, keyEquivalent: "n")
        item.keyEquivalentModifierMask = .command
        item.target = actions.target
        item.identifier = NSUserInterfaceItemIdentifier("menu.add-account")
        return item
    }

    private static func makeAccountItem(
        account: StoredAccountMeta,
        presentation: AccountPresentation,
        refreshState: RefreshState,
        issue: AccountIssuePresentation?,
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let balance = account.balanceDisplayText ?? "—"
        let isRefreshing: Bool = if case .refreshing = refreshState { true } else { false }
        let subtitleText: String? = isRefreshing ? "Refreshing…" : issue?.sidebarHint

        let item = NSMenuItem(title: presentation.name, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = account.id
        item.identifier = NSUserInterfaceItemIdentifier("menu.account.\(account.id)")
        // The badge sits in the trailing column, so balances end where the shortcuts end.
        item.badge = NSMenuItemBadge(string: balance)
        item.toolTip = balance

        if let subtitleText {
            if #available(macOS 14.4, *) {
                item.subtitle = subtitleText
            } else {
                let attributed = NSMutableAttributedString(
                    string: presentation.name,
                    attributes: [.font: NSFont.menuFont(ofSize: 0)]
                )
                attributed.append(NSAttributedString(
                    string: "\n\(subtitleText)",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: issue?.tintColor ?? NSColor.secondaryLabelColor,
                    ]
                ))
                item.attributedTitle = attributed
            }
        }

        return item
    }
}
