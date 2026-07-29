import Foundation

@MainActor
protocol MenuBarPopoverManaging: AnyObject {
    var isPresented: Bool { get }

    func present()
    func dismiss()
}

@MainActor
final class MenuBarInteractionController {
    private let popover: MenuBarPopoverManaging

    init(popover: MenuBarPopoverManaging) {
        self.popover = popover
    }

    func handleClick(clickCount: Int) {
        guard clickCount == 1 else { return }

        if popover.isPresented {
            popover.dismiss()
        } else {
            popover.present()
        }
    }
}
