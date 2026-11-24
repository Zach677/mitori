//
//  DockIconPolicyController.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/24.
//

import AppKit

@MainActor
final class DockIconPolicyController {
    private let hidesWhenClosed: @MainActor () -> Bool
    private let hasVisibleWindow: @MainActor () -> Bool
    private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private(set) var currentPolicy: NSApplication.ActivationPolicy = .accessory

    init(
        hidesWhenClosed: @escaping @MainActor () -> Bool,
        hasVisibleWindow: @escaping @MainActor () -> Bool,
        applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { policy in
            if NSApp.activationPolicy() != policy {
                NSApp.setActivationPolicy(policy)
            }
        }
    ) {
        self.hidesWhenClosed = hidesWhenClosed
        self.hasVisibleWindow = hasVisibleWindow
        self.applyPolicy = applyPolicy
    }

    func update() {
        let target: NSApplication.ActivationPolicy = if !hidesWhenClosed() || hasVisibleWindow() {
            .regular
        } else {
            .accessory
        }
        guard target != currentPolicy else { return }
        currentPolicy = target
        applyPolicy(target)
    }
}
