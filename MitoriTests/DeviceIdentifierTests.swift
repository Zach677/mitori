//
//  DeviceIdentifierTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/10/15.
//

import Foundation
import Testing

@testable import Mitori

struct DeviceIdentifierTests {
    @Test(arguments: [
        ([0x3C, 0x22, 0xFB, 0x01, 0x02, 0x03], "3C22FB010203"),
    ] as [([UInt8], String)])
    func formatsAHardwareAddress(bytes: [UInt8], expected: String) {
        #expect(DeviceIdentifier.identifier(fromMACAddress: Data(bytes)) == expected)
    }

    // macOS 27 redacts addresses as 02:00:00:00:00:00; multicast and empty addresses are not identities.
    @Test(arguments: [
        [0x02, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0],
        [0x01, 0x22, 0xFB, 0x01, 0x02, 0x03],
        [0x3C, 0x22, 0xFB, 0x01, 0x02],
    ] as [[UInt8]])
    func rejectsUnusableAddresses(bytes: [UInt8]) {
        #expect(DeviceIdentifier.identifier(fromMACAddress: Data(bytes)) == nil)
    }

    // A runner without a hardware interface uses the persisted fallback instead.
    @Test(.enabled(
        if: (try? DeviceIdentifier.system()) != nil,
        "No hardware address is readable on this host."
    ))
    func systemIdentifierIsStableHardwareHex() throws {
        let first = try DeviceIdentifier.system()

        #expect(first.count == 12)
        #expect(first.allSatisfy { $0.isHexDigit && !$0.isLowercase })
        #expect(first != "020000000000")
        #expect(try DeviceIdentifier.system() == first)
    }

    @Test
    func fallbackIsGeneratedOnceAndReused() throws {
        let suiteName = "dev.zach.mitori.tests.device-identifier.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = DeviceIdentifierProvider.make(system: { throw CocoaError(.featureUnsupported) }, defaults: defaults)
        let second = DeviceIdentifierProvider.make(system: { throw CocoaError(.featureUnsupported) }, defaults: defaults)

        #expect(first.count == 12)
        #expect(second == first)
    }

    @Test
    func systemIdentifierWinsOverTheFallback() throws {
        let suiteName = "dev.zach.mitori.tests.device-identifier.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(DeviceIdentifierProvider.make(system: { "3C22FB010203" }, defaults: defaults) == "3C22FB010203")
    }
}
