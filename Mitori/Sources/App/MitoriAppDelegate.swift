import AppKit
import Foundation

@MainActor
final class MitoriAppDelegate: NSObject, NSApplicationDelegate {
    private let presenter = LaunchHaloPresenter.live()
    private let model = MitoriModel.live()
    private lazy var menuBarController = MenuBarController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = menuBarController

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            presenter.presentIfNeeded()
        }
    }
}
