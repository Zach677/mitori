//
//  MitoriMain.swift
//  Mitori
//
//  Created by @Zach677 on 2026/05/30.
//

import AppKit

@main
enum MitoriMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MitoriAppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
