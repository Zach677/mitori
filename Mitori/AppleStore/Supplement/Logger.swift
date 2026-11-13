//
//  Logger.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation
import os

public enum APLogger {
    // Interpolated values stay private in the unified log (I-8).
    private static let logger = Logger(subsystem: "dev.zach.mitori", category: "AppleStore")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .private)")
    }
}
