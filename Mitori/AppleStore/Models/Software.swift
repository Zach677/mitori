//
//  Software.swift
//  ApplePackage
//
//  Created by qaq on 2025/9/14.
//

import Foundation

public struct Software: Codable, Equatable, Hashable, Identifiable {
    public var id: Int64
    public var bundleID: String
    public var name: String

    private enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case bundleID = "bundleId"
        case name = "trackName"
    }
}
