//
//  Strings.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation

public enum Strings {
    // MARK: - Authentication

    static let invalidAuthEndpoint = "invalid auth endpoint URL"

    // MARK: - Common Response

    static let responseBodyEmpty = "response body is empty"
    static let responseNotDictionary = "response is not a dictionary"

    // MARK: - Account

    static let emptyEmail = "empty email"
    static let emptyPassword = "empty password"
    static let unknownStoreIdentifier = "unknown store identifier"
    static let unableToReadAppleId = "unable to read appleId"
    static let unableToReadFirstName = "unable to read firstName"
    static let unableToReadLastName = "unable to read lastName"
    static let unableToReadPasswordToken = "unable to read passwordToken"
    static let unableToReadDsPersonId = "unable to read dsPersonId"
    static let missingAccountInfo = "missing accountInfo"
    static let missingAddress = "missing address"

    static func unsupportedStoreIdentifier(_ id: String) -> String {
        "unsupported store identifier: \(id)"
    }
}
