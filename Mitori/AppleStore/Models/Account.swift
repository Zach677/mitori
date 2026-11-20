//
//  Account.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

struct Account: Codable, Hashable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    // Keep identifiers and personal data out of interpolated strings (I-8).
    var description: String {
        "Account(store: \(store), pod: \(pod ?? "nil"))"
    }

    var debugDescription: String {
        description
    }

    var email: String
    var password: String

    var appleId: String // /accountInfo/appleId
    var store: String
    var firstName: String // /accountInfo/address/firstName
    var lastName: String // /accountInfo/address/lastName
    var passwordToken: String // /passwordToken
    var directoryServicesIdentifier: String // /dsPersonId
    var cookie: [Cookie]
    var pod: String?

    init(
        email: String,
        password: String,
        appleId: String,
        store: String,
        firstName: String,
        lastName: String,
        passwordToken: String,
        directoryServicesIdentifier: String,
        cookie: [Cookie],
        pod: String? = nil
    ) {
        self.email = email
        self.password = password
        self.appleId = appleId
        self.store = store
        self.firstName = firstName
        self.lastName = lastName
        self.passwordToken = passwordToken
        self.directoryServicesIdentifier = directoryServicesIdentifier
        self.cookie = cookie
        self.pod = pod
    }
}

extension Account {
    init(
        email: String,
        password: String,
        appleId: String?,
        store: String,
        firstName: String?,
        lastName: String?,
        passwordToken: String?,
        directoryServicesIdentifier: String?,
        cookie: [Cookie],
        pod: String? = nil
    ) throws {
        try ensure(!email.isEmpty, Strings.emptyEmail)
        try ensure(!password.isEmpty, Strings.emptyPassword)
        self.email = email
        self.password = password
        self.appleId = try appleId.get(Strings.unableToReadAppleId)
        try ensure(!store.isEmpty, Strings.unknownStoreIdentifier)
        try ensure(Configuration.countryCode(for: store) != nil, Strings.unsupportedStoreIdentifier(store))
        self.store = store
        self.firstName = try firstName.get(Strings.unableToReadFirstName)
        self.lastName = try lastName.get(Strings.unableToReadLastName)
        self.passwordToken = try passwordToken.get(Strings.unableToReadPasswordToken)
        self.directoryServicesIdentifier = try directoryServicesIdentifier.get(Strings.unableToReadDsPersonId)
        self.cookie = cookie
        self.pod = pod
    }
}
