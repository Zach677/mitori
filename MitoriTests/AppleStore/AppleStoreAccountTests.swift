import Foundation
import Testing

@testable import Mitori

// Ported from ApplePackage Tests/ApplePackageTests/AccountTests.swift at 3b535f1.
struct AppleStoreAccountTests {
    @Test
    func accountCodableWithPod() throws {
        let account = Account(
            email: "test@example.com",
            password: "pass",
            appleId: "123",
            store: "143441",
            firstName: "John",
            lastName: "Doe",
            passwordToken: "token",
            directoryServicesIdentifier: "ds123",
            cookie: [],
            pod: "42"
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.pod == "42")
        #expect(decoded.email == "test@example.com")
    }

    @Test
    func accountCodableWithoutPod() throws {
        let account = Account(
            email: "test@example.com",
            password: "pass",
            appleId: "123",
            store: "143441",
            firstName: "John",
            lastName: "Doe",
            passwordToken: "token",
            directoryServicesIdentifier: "ds123",
            cookie: []
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.pod == nil)
    }

    @Test
    func accountBackwardCompatibility() throws {
        // Simulate an old account.json without the pod field
        let json = """
        {
            "email": "test@example.com",
            "password": "pass",
            "appleId": "123",
            "store": "143441",
            "firstName": "John",
            "lastName": "Doe",
            "passwordToken": "token",
            "directoryServicesIdentifier": "ds123",
            "cookie": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.pod == nil)
        #expect(decoded.email == "test@example.com")
        #expect(decoded.store == "143441")
    }

    @Test
    func accountValidationInit() throws {
        let appleId: String? = "123"
        let account = try Account(
            email: "test@example.com",
            password: "pass",
            appleId: appleId,
            store: "143441",
            firstName: "John" as String?,
            lastName: "Doe" as String?,
            passwordToken: "token" as String?,
            directoryServicesIdentifier: "ds123" as String?,
            cookie: [],
            pod: "99"
        )
        #expect(account.pod == "99")
    }

    @Test(arguments: [
        ("", "pass", "123", "143441"),
        ("test@example.com", "", "123", "143441"),
        ("test@example.com", "pass", "123", "999999"),
        ("test@example.com", "pass", nil, "143441"),
    ] as [(String, String, String?, String)])
    func accountValidationInitRejectsInvalidInput(email: String, password: String, appleId: String?, store: String) {
        #expect(throws: (any Error).self) {
            try Account(
                email: email,
                password: password,
                appleId: appleId,
                store: store,
                firstName: "John" as String?,
                lastName: "Doe" as String?,
                passwordToken: "token" as String?,
                directoryServicesIdentifier: "ds123" as String?,
                cookie: []
            )
        }
    }
}
