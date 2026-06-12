import Foundation

@MainActor
enum StatusItemClickKind {
    case primary
    case secondary
}

@MainActor
protocol MenuBarPopoverManaging: AnyObject {
    var isPresented: Bool { get }

    func present()
    func dismiss()
}

@MainActor
protocol MenuBarContextMenuManaging: AnyObject {
    func present()
}

@MainActor
final class MenuBarInteractionController {
    private let popover: MenuBarPopoverManaging
    private let contextMenu: MenuBarContextMenuManaging

    init(popover: MenuBarPopoverManaging, contextMenu: MenuBarContextMenuManaging) {
        self.popover = popover
        self.contextMenu = contextMenu
    }

    func handleClick(_ kind: StatusItemClickKind) {
        switch kind {
        case .primary:
            if popover.isPresented {
                popover.dismiss()
            } else {
                popover.present()
            }
        case .secondary:
            if popover.isPresented {
                popover.dismiss()
            }
            contextMenu.present()
        }
    }
}
