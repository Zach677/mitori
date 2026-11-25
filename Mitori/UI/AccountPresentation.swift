//
//  AccountPresentation.swift
//  Mitori
//
//  Created by @Zach677 on 2026/08/01.
//

import Foundation

struct AccountPresentation {
    let name: String
    let windowTitle: String
    let appleID: String
    let deviceIdentifier: String

    init(
        account: StoredAccountMeta,
        accountIndex: Int,
        hidesPersonalInformation: Bool
    ) {
        guard hidesPersonalInformation else {
            name = account.displayName
            windowTitle = account.displayName
            appleID = account.appleID
            deviceIdentifier = account.deviceIdentifier
            return
        }

        name = "Account \(accountIndex + 1)"
        windowTitle = "Account Details"
        appleID = "Hidden"
        deviceIdentifier = "Hidden"
    }
}

extension Date {
    /// "Nov 21 at 14:02", with the year only when it differs from `now`'s year.
    func shortTimestamp(relativeTo now: Date = .now) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        let sameYear = Calendar.current.isDate(self, equalTo: now, toGranularity: .year)
        return formatted(sameYear ? style : style.year())
    }

    /// "just now" or "4 minutes ago" within a day; `shortTimestamp` otherwise.
    func freshnessText(relativeTo now: Date = .now) -> String {
        let age = now.timeIntervalSince(self)
        guard age >= 0, age < 24 * 60 * 60 else { return shortTimestamp(relativeTo: now) }
        if age < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: now)
    }
}
