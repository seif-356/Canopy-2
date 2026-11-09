import SwiftUI

@main
struct Canopy2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.desktopSkin) private var desktopSkin = false

    var body: some Scene {
        // The app has no Dock icon (LSUIElement), so the menu bar item is
        // the way to reach Settings and Quit.
        MenuBarExtra("Canopy 2", systemImage: "rectangle.topthird.inset.filled") {
            Toggle("Desktop Skin", isOn: $desktopSkin)
            Divider()
            Button("Settings…") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit Canopy 2") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
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
        SettingsWindowController.shared.configure(controller: controller)
        controller.start()
        controller.showHello()
        notchController = controller
    }

    /// Opening the app again while it runs (e.g. double-clicking it in Finder) shows the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notchController?.showHello()
        return false
    }
}
