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
            Button("Night Mode") {
                NightModeController.shared.toggle()
            }
            .keyboardShortcut("n")
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
        // A helper (osascript, perl) exiting early must not kill the app when we write to it.
        signal(SIGPIPE, SIG_IGN)
        Prefs.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        let controller = NotchController()
        SettingsWindowController.shared.configure(controller: controller)
        controller.start()
        if let scene = UserDefaults.standard.string(forKey: "smokeScene") {
            // CI screenshot run: give media a moment to load, then set up the scene.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                controller.runSmokeScene(scene)
            }
        } else {
            controller.showHello()
        }
        notchController = controller
    }

    /// Opening the app again while it runs (e.g. double-clicking it in Finder) shows the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notchController?.showHello()
        return false
    }
}
