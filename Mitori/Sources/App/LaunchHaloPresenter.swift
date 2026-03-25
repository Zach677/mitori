import AppKit
import Foundation

@MainActor
protocol LaunchHaloDisplaying: AnyObject {
    func showLaunchHalo()
}

@MainActor
final class LaunchHaloPresenter {
    private let displaying: LaunchHaloDisplaying
    private var hasPresented = false

    init(displaying: LaunchHaloDisplaying) {
        self.displaying = displaying
    }

    func presentIfNeeded() {
        guard !hasPresented else {
            return
        }

        hasPresented = true
        displaying.showLaunchHalo()
    }
}

extension LaunchHaloPresenter {
    static func live() -> LaunchHaloPresenter {
        LaunchHaloPresenter(displaying: LaunchHaloWindowController())
    }
}

@MainActor
final class LaunchHaloAppDelegate: NSObject, NSApplicationDelegate {
    private let presenter = LaunchHaloPresenter.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            presenter.presentIfNeeded()
        }
    }
}
