import SwiftUI

@main
struct MitoriApp: App {
    @NSApplicationDelegateAdaptor(LaunchHaloAppDelegate.self) private var appDelegate
    @State private var model = MitoriModel.live()

    var body: some Scene {
        MenuBarExtra("Mitori", systemImage: "creditcard.and.123") {
            RootMenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
