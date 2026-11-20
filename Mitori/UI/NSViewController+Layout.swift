//
//  NSViewController+Layout.swift
//  Mitori
//
//  Created by @Zach677 on 2026/11/16.
//

import AppKit

extension NSViewController {
    /// Adds `view` to a vertical stack and makes it as wide as the stack inside its edge insets.
    func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        let horizontalInsets = stack.edgeInsets.left + stack.edgeInsets.right
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -horizontalInsets).isActive = true
    }
}
