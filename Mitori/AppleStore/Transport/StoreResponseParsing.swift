//
//  StoreResponseParsing.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/20.
//

import Foundation

enum StoreResponseHeaders {
    static func storefront(from response: HTTPURLResponse) -> String? {
        guard let storefront = response.value(forHTTPHeaderField: "x-set-apple-store-front")?
            .components(separatedBy: "-")
            .first,
            !storefront.isEmpty
        else {
            return nil
        }
        return storefront
    }

    static func pod(from response: HTTPURLResponse) -> String? {
        guard let pod = response.value(forHTTPHeaderField: "pod"), !pod.isEmpty else {
            return nil
        }
        return pod
    }

    /// Reads `failureType` whether Apple encodes it as a string or integer in the plist.
    static func failureType(in plist: [String: Any]) -> String? {
        guard let raw = plist["failureType"] else { return nil }
        if let string = raw as? String {
            return string
        }
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return nil
    }
}
