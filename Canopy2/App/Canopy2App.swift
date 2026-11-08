import SwiftUI

@main
struct Canopy2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no Dock icon (LSUIElement), so the menu bar item is
        // the way to reach Settings and Quit.
        MenuBarExtra("Canopy 2", systemImage: "rectangle.topthird.inset.filled") {
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit Canopy 2") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        let controller = NotchController()
        controller.start()
        notchController = controller
    }
}
