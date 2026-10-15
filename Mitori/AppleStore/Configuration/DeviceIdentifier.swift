//
//  DeviceIdentifier.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation
#if os(macOS)
    import IOKit
#endif

public enum DeviceIdentifier {
    /// The permanent hardware MAC of the primary network interface. The BSD
    /// link address can be a rotating private Wi-Fi address, and macOS 27 can
    /// redact it as 02:00:00:00:00:00, so read the address from IOKit.
    public static func system() throws -> String {
        #if os(iOS)
            // https://developer.apple.com/library/archive/releasenotes/General/WhatsNewIniOS/Articles/iOS7.html#:~:text=returns%20the%20value-,02:00:00:00:00:00,-.%20If%20you%20need
            try ensureFailed("will always return: 02:00:00:00:00:00")
        #else
            let bsdNames: [String] = ["en0", "en1"]
            let candidates = [primaryInterfaceMatching()] + bsdNames.map { name -> CFMutableDictionary? in
                IOBSDNameMatching(kIOMainPortDefault, 0, name)
            }
            for matching in candidates {
                if let identifier = hardwareIdentifier(matching: matching) {
                    return identifier
                }
            }
            try ensureFailed("unable to read a hardware mac address")
        #endif
    }

    static func identifier(fromMACAddress address: Data) -> String? {
        guard address.count == 6,
              address[address.startIndex] & 1 == 0,
              address != Data(count: 6),
              address != Data([0x02, 0, 0, 0, 0, 0])
        else {
            return nil
        }
        return address.map { String(format: "%02X", $0) }.joined()
    }

    #if os(macOS)
        private static func primaryInterfaceMatching() -> CFMutableDictionary? {
            guard let matching = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary? else { return nil }
            matching["IOPropertyMatch"] = ["IOPrimaryInterface": true]
            return matching
        }

        private static func hardwareIdentifier(matching: CFMutableDictionary?) -> String? {
            guard let matching else { return nil }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            guard service != 0 else { return nil }
            defer { IOObjectRelease(service) }
            let address = IORegistryEntrySearchCFProperty(
                service,
                kIOServicePlane,
                "IOMACAddress" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            )
            return (address as? Data).flatMap(identifier(fromMACAddress:))
        }
    #endif

    public static func random() -> String {
        let chars = [
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "A", "B", "C", "D", "E", "F",
        ]
        var ans = ""
        while ans.count < 12 {
            ans.append(chars.randomElement()!)
        }
        return ans
    }
}
