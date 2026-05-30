import AppKit

@main
enum MitoriMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MitoriAppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
