import AppKit
import SwiftUI

@MainActor
final class LaunchHaloWindowController: LaunchHaloDisplaying {
    private static let panelSize = NSSize(width: 148, height: 48)

    private weak var panel: NSPanel?

    func showLaunchHalo() {
        closeCurrentPanel()

        let panel = LaunchHaloPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setFrameOrigin(panelOrigin())
        panel.contentViewController = NSHostingController(
            rootView: LaunchHaloView { [weak self, weak panel] in
                guard let self, let panel else {
                    return
                }

                self.close(panel)
            }
        )

        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func panelOrigin() -> NSPoint {
        let screen = screenForHalo()
        return NSPoint(
            x: screen.frame.maxX - Self.panelSize.width - 18,
            y: screen.visibleFrame.maxY - Self.panelSize.height - 8
        )
    }

    private func screenForHalo() -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func closeCurrentPanel() {
        guard let panel else {
            return
        }

        close(panel)
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.close()
        if self.panel === panel {
            self.panel = nil
        }
    }
}

private final class LaunchHaloPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct LaunchHaloView: View {
    let onDismiss: @MainActor () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 24, height: 24)

                Image(systemName: "message.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("halo")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        .scaleEffect(isVisible ? 1 : 0.92)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .padding(6)
        .task {
            await runAnimation()
        }
    }

    @MainActor
    private func runAnimation() async {
        withAnimation(.snappy(duration: 0.28, extraBounce: 0.08)) {
            isVisible = true
        }

        try? await Task.sleep(for: .seconds(2.2))

        withAnimation(.easeInOut(duration: 0.22)) {
            isVisible = false
        }

        try? await Task.sleep(for: .milliseconds(220))
        onDismiss()
    }
}
