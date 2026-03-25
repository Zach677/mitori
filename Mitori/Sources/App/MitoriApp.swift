import SwiftUI

@main
struct MitoriApp: App {
    @NSApplicationDelegateAdaptor(MitoriAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
