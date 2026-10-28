import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["hoverDelay": 1.8])
        let dir = URL.applicationSupportDirectory.appending(path: "Tuck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        notch = NotchController(model: NotchModel(fileURL: dir.appending(path: "todos.json")))
        _ = updater  // starts Sparkle's scheduled checks

        // Tuck is meant to always be there: open at login once by default; the menu can turn it off again.
        if isBundled, !UserDefaults.standard.bool(forKey: "didEnableLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didEnableLoginItem")
        }
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)  // no Dock icon, no menu bar; LSUIElement does the same in the .app
NSApplication.shared.run()
