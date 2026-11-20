//
//  Software.swift
//  ApplePackage
//
//  Created by qaq on 2025/9/14.
//

import Foundation

struct Software: Codable, Equatable, Hashable, Identifiable {
    var id: Int64
    var bundleID: String
    var name: String

    private enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case bundleID = "bundleId"
        case name = "trackName"
    }
}
