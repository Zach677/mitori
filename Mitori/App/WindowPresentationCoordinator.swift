import Foundation

@MainActor
protocol WindowVisibilityManaging: AnyObject {
    var isVisible: Bool { get }

    func show()
    func focus()
}

@MainActor
final class WindowPresentationCoordinator {
    private let window: WindowVisibilityManaging

    init(window: WindowVisibilityManaging) {
        self.window = window
    }

    func present() {
        if window.isVisible {
            window.focus()
        } else {
            window.show()
        }
    }
}
